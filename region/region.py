#
# Copyright 2015 CREATE-NET <abroglio AT create-net DOT org>
#
# Author: Attilio Broglio <abroglio AT create-net DOT org>
#
# Version: 1.0.3
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

from __future__ import absolute_import

from oslo.config import cfg
from oslo.utils import timeutils
from ceilometer.openstack.common import log
from ceilometer.agent import plugin_base
from ceilometer import sample
from neutronclient.v2_0 import client as clientN
from netaddr import *
from ceilometer.region import OSVersionComponent

LOG = log.getLogger(__name__)

tmp_grp = [
    cfg.StrOpt('location', default=None, help='no descr'),
    cfg.FloatOpt('latitude', default=None, help='no descr'),
    cfg.FloatOpt('longitude', default=None, help='no descr'),
    cfg.ListOpt('netlist', default=None, help='no descr'),
    cfg.FloatOpt('ram_allocation_ratio', default=None, help='no descr'),
    cfg.FloatOpt('cpu_allocation_ratio', default=None, help='no descr'),
]

cfg.CONF.register_opts(tmp_grp, group='region')

metaD = {
    "name": None,
    "latitude": None,
    "longitude": None,
    "location": None,
    "ram_allocation_ratio": None,
    "cpu_allocation_ratio": None
}


class _Base(plugin_base.PollsterBase):

    @property
    def default_discovery(self):
        return 'endpoint:%s' % cfg.CONF.service_types.nova


class RegionPollster(_Base):
    def get_samples(self, manager, cache, resources):
        neutron = clientN.Client(
            username=cfg.CONF.service_credentials.os_username,
            password=cfg.CONF.service_credentials.os_password,
            tenant_name=cfg.CONF.service_credentials.os_tenant_name,
            auth_url=cfg.CONF.service_credentials.os_auth_url,
            region_name=cfg.CONF.service_credentials.os_region_name
        )

        # initialize some variables:
        pool_size = 0
        alloc_ip = 0
        used_ip = 0
        subNet = list()
        subNetId = list()
        regionArray = list()
        try:
            nL = neutron.list_networks()
        except Exception as e:
            LOG.error(e)
            raise e

        # compute the size of the pool
        if nL and "networks" in nL:
            for nLi in nL["networks"]:
                if ("id" in nLi) and ("name" in nLi) and nLi["name"] in cfg.CONF.region.netlist and  ("subnets" in nLi):
                    for sNi in nLi['subnets']:
                        sN = neutron.show_subnet(sNi)
                        if ("subnet" in sN) and ("cidr" in sN["subnet"]) and ("allocation_pools" in sN["subnet"]):
                            subNetId.append(sN['subnet']['id'])
                            if sN["subnet"]["allocation_pools"] and len(sN["subnet"]["allocation_pools"]) > 0:
                                for pool in sN["subnet"]["allocation_pools"]:
                                    subNet.append(IPRange(pool["start"], pool["end"]))
                                    pool_size += IPRange(pool["start"], pool["end"]).size

        # compute the IP usage
        netF = neutron.list_floatingips()
        if netF and "floatingips" in netF:
            for netFi in netF["floatingips"]:
                for tmp_pool in subNet:
                    if "floating_ip_address" in netFi and IPAddress(netFi["floating_ip_address"]) in tmp_pool:
                        alloc_ip += 1
                        if "fixed_ip_address" in netFi and netFi["fixed_ip_address"]:
                            used_ip += 1
                            break
                        break

        # check if some routers are using IPs
        r_L = neutron.list_routers()
        if "routers" in r_L:
            for r_li in r_L["routers"]:
                if "external_gateway_info" in r_li \
                        and r_li["external_gateway_info"] \
                        and "external_fixed_ips" in r_li["external_gateway_info"] \
                        and len(r_li["external_gateway_info"]["external_fixed_ips"]) > 0:
                    for tmp_r_id in r_li["external_gateway_info"]  ["external_fixed_ips"]:
                        if "subnet_id" in tmp_r_id and tmp_r_id["subnet_id"] in subNetId:
                            alloc_ip += 1
                            used_ip += 1

        # create region Object
        # build metadata
        metaD["name"] = (cfg.CONF.service_credentials.os_region_name if cfg.CONF.service_credentials.os_region_name else None)
        metaD["latitude"] = (cfg.CONF.region.latitude if cfg.CONF.region.latitude else 0.0)
        metaD["longitude"] = (cfg.CONF.region.longitude if cfg.CONF.region.longitude else 0.0)
        metaD["location"] = (cfg.CONF.region.location if cfg.CONF.region.location else None)
        metaD["ram_allocation_ratio"] = (cfg.CONF.region.ram_allocation_ratio if cfg.CONF.region.ram_allocation_ratio else None)
        metaD["cpu_allocation_ratio"] = (cfg.CONF.region.cpu_allocation_ratio if cfg.CONF.region.cpu_allocation_ratio else None)

        # store components versions as metadata
        manager = OSVersionComponent.OpenStackComponentVersionManager()
        c_versions = manager.get_all_components_version()
        for c in c_versions:
            if c['isInstalled']:
                name = c['component'] + "_version"
                version = c['attributes']['version']
                metaD[name] = version
            else:
                LOG.debug("Component not intalled: %s " % (c))

        LOG.debug("Publish region metadata: %s " % (metaD))

        # build samples
        regionArray.append({'name': 'region.pool_ip', 'unit': '#', 'value': (pool_size if pool_size else 0)})
        regionArray.append({'name': 'region.allocated_ip', 'unit': '#', 'value': (alloc_ip if alloc_ip else 0)})
        regionArray.append({'name': 'region.used_ip', 'unit': '#', 'value': (used_ip if used_ip else 0)})

        # loop over the region Object
        for regionInfo in regionArray:
            my_sample = sample.Sample(
                name=regionInfo['name'],
                type="gauge",
                unit=regionInfo['unit'],
                volume=regionInfo['value'],
                user_id=None,
                project_id=None,
                resource_id=cfg.CONF.service_credentials.os_region_name,
                timestamp=timeutils.isotime(),
                resource_metadata=metaD
            )
            LOG.debug("Publish sample: %s" % (my_sample))
            yield my_sample
