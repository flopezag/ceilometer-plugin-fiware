#
# Copyright 2015 CREATE-NET <abroglio AT create-net DOT org>
#
# Author: Attilio Broglio <abroglio AT create-net DOT org>
#
# Version: 1.0.1
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

from ceilometer.openstack.common import log
from ceilometer.compute import pollsters
from ceilometer.i18n import _, _LW
from ceilometer import sample
from oslo.utils import timeutils
from oslo.config import cfg
from novaclient import client

LOG = log.getLogger(__name__)


class HostPollster(pollsters.BaseComputePollster):

    @property
    def default_discovery(self):
        return 'local_node'

    @staticmethod
    def get_samples(manager, cache, resources):
        nt = client.Client(
            version=2,
            username=cfg.CONF.service_credentials.os_username,
            api_key=cfg.CONF.service_credentials.os_password,
            project_id=cfg.CONF.service_credentials.os_tenant_name,
            auth_url=cfg.CONF.service_credentials.os_auth_url,
            region_name=cfg.CONF.service_credentials.os_region_name)

        host = cfg.CONF.host
        nodename = cfg.CONF.host
        LOG.debug(_('checking host %s'), host)
        try:
            info = nt.hosts.get(host)
            values = []
            if len(info) >= 3:
                # total
                values.append({'name': 'ram.tot', 'unit': 'MB', 'value': (info[0].memory_mb if info[0].memory_mb else 0)})
                values.append({'name': 'disk.tot', 'unit': 'GB', 'value': (info[0].disk_gb if info[0].disk_gb else 0)})
                values.append({'name': 'cpu.tot', 'unit': 'cpu', 'value': (info[0].cpu if info[0].cpu else 0)})
                # now
                values.append({'name': 'ram.now', 'unit': 'MB', 'value': (info[1].memory_mb if info[1].memory_mb else 0)})
                values.append({'name': 'disk.now', 'unit': 'GB', 'value': (info[1].disk_gb if info[1].disk_gb else 0)})
                values.append({'name': 'cpu.now', 'unit': 'cpu', 'value': (info[1].cpu if info[1].cpu else 0)})
                # max
                values.append({'name': 'ram.max', 'unit': 'MB', 'value': (info[2].memory_mb if info[2].memory_mb else 0)})
                values.append({'name': 'disk.max', 'unit': 'GB', 'value': (info[2].disk_gb if info[2].disk_gb else 0)})
                values.append({'name': 'cpu.max', 'unit': 'cpu', 'value': (info[2].cpu if info[2].cpu else 0)})

            for item in values:
                yield sample.Sample(
                    name="compute.node.%s" % item['name'],
                    type=sample.TYPE_GAUGE,
                    unit=item['unit'],
                    volume=item['value'],
                    user_id=None,
                    project_id=None,
                    resource_id="%s_%s" % (host, nodename),
                    timestamp=timeutils.isotime(),
                    resource_metadata={}
                )

        except Exception as err:
            LOG.exception(_('could not get info for host %(host)s: %(e)s'), {'host': host, 'e': err})
