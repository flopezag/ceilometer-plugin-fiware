# FIWARE Lab monitoring system (based on Ceilometer and Monasca)

## Description

The following figure describes the high level architecture of the monitoring system.

![FIWARE Monitoring Architecture][fiware_monitoring_architecture_pict]

Data is collected through [Ceilometer][ceilometer] (where customized pollsters have been developed) from each node.
Relevant metrics are sent to [Monasca][monasca] on master node using [Monasca-Ceilometer][monasca_ceilometer] plugin.
Additionally, the external [Sanity Check][fihealth_sanity_checks] tool from FIHealth publishes the sanity status of the
nodes directly to Monasca.

Monitoring data is stored at Monasca master node and eventually passed to the [FIWARE Big Data GE (Cosmos)][cosmos] for
aggregation and analysis. [FIWARE Lab Monitoring API][fiware_lab_monitoring_api] component makes such data available to
different clients, particularly to [Infographics][fiware_lab_infographics]. This way Infrastructure Owners (IOs) should
be able to track the following resources of their Openstack environments:
- __region__
- __hosts__
- __images__
- __host services__ _(OpenStack services: nova, glance, cinder, ... )_
- __instances__ (i.e. VMs)

Some additional information about Ceilometer: _it is a tool created in order to handle the [Telemetry][telemetry]
requirements of an OpenStack environment (this includes use cases such as metering, monitoring, and alarming to
name a few)_.

![Ceilometer Architecture][ceilometer_architecture_pict]
_Figure taken from [Ceilometer documentation][ceilometer_architecture_doc]_


## Installation

The installation and configuration procedure involves both *Central agent pollsters* at the controller nodes and
*Compute agent pollsters* at every compute node. This repository contains all the pollsters and files that IOs would
need to customize the default Ceilometer installation.

### Controller(s)

#### Pollster for region

Please follow these steps:

1. Open the file `/etc/ceilometer/ceilometer.conf` and add these entries (_with your region values_) at the end:

   ```
   [region]
   latitude=1.1
   longitude=12.2
   location=IT
   netlist=net04_ext,net05_ext
   ram_allocation_ratio=1.5
   cpu_allocation_ratio=16
   ```

   Pay attention to the `netlist` attribute: the names of external networks in your OpenStack installation.

2. Locate the installation directory of Ceilometer package (usually, `pip` command shows such information):

   ```
   # pip show ceilometer
   ---
   Name: ceilometer
   Version: 2015.1.1
   Location: /usr/lib/python2.7/dist-packages
   ```

   In this documentation we will refer to such location as `$PYTHON_SITE_PKG`.

3. Copy [region](/region) directory structure from this repository into Ceilometer package location (by default, at
   `$PYTHON_SITE_PKG/ceilometer`). After that, `RegionPollster` class should be available:

   ```
   # python -c 'from ceilometer.region import region; print region.RegionPollster().__class__'
   <class 'ceilometer.region.region.RegionPollster'>
   ```

4. Locate the entry points file for Ceilometer (which depends on the version: for 2015.1.1, should be located at
   path `$PYTHON_SITE_PKG/ceilometer-2015.1.1.egg-info/entry_points.txt`) and please add the new pollster at the
   `[ceilometer.poll.central]` section:

   ```
   region = ceilometer.region.region:RegionPollster
   ```

5. Restart Ceilometer Central Agent:

   If using Fuel HA:
   ```
   # crm resource restart p_ceilometer-agent-central
   ```
   Otherwise:
   ```
   # service ceilometer-agent-central restart
   ```

#### Pollster for image

__NOT NEEDED IF YOU HAVE A CEILOMETER FOR OPENSTACK KILO__

The pollster for the images is already provided by a standard installation of Ceilometer. Please check if it is included
in entry points:

1. Open the entry points file and look for this entry at the `[ceilometer.notification]` section:

   ```
   image = ceilometer.image.notifications:Image
   ```


### Compute nodes

#### Pollster for hosts

1. Add these entries to the file `/etc/nova/nova.conf` at section `[DEFAULT]` and restart the __nova-compute__ service:

   ```
   compute_monitors = ComputeDriverCPUMonitor
   notification_driver = messagingv2
   ```

2. Copy [host.py](/compute_pollster/host.py) file from the [compute_pollster](/compute_pollster) directory of this
   repository into the `compute/pollsters/` subdirectory at Ceilometer package location. After that, `HostPollster`
   class should be available:

   ```
   # python -c 'from ceilometer.compute.pollsters import host; print host.HostPollster().__class__'
   <class 'ceilometer.compute.pollsters.host.HostPollster'>
   ```

3. Edit entry points file to add the new pollster at the `[ceilometer.poll.compute]` section:

   ```
   compute.info = ceilometer.compute.pollsters.host:HostPollster
   ```

4. Please check the polling frequency defined by `interval` parameter at `/etc/ceilometer/pipeline.yaml`. Its default
   value is 60 seconds: you may consider lowering the polling rate.

5. Restart both Nova Compute and Ceilometer Compute Agent:

   ```
   # service nova-compute restart
   # service ceilometer-agent-compute restart
   ```

#### Pollster for vm

__NOT NEEDED IF YOU HAVE A CEILOMETER FOR OPENSTACK KILO__

1. Replace file `$PYTHON_SITE_PKG/ceilometer/compute/virt/inspector.py` with that at location
   [virt/inspector.py](/virt/inspector.py) in this repository

2. Replace file `$PYTHON_SITE_PKG/ceilometer/compute/virt/libvirt/inspector.py` with that at location
   [virt/libvirt/inspector.py](/virt/libvirt/inspector.py) in this repository

3. Replace file `$PYTHON_SITE_PKG/ceilometer/compute/pollsters/memory.py` with that at location
   [compute_pollster/memory.py](/compute_pollster/memory.py) in this repository

4. Replace file `$PYTHON_SITE_PKG/ceilometer/compute/pollsters/disk.py` with that at location
   [compute_pollster/disk.py](/compute_pollster/disk.py) in this repository

5. Edit entry points file and ensure these entries are found at their respective sections:

   ```
   [ceilometer.notification]
   memory = ceilometer.compute.notifications.instance:Memory
   ```
   ```
   [ceilometer.poll.compute]
   memory.usage = ceilometer.compute.pollsters.memory:MemoryUsagePollster
   disk.capacity = ceilometer.compute.pollsters.disk:CapacityPollster
   disk.usage = ceilometer.compute.pollsters.disk:PhysicalPollster
   ```

#### Configuration files

1. Copy (or merge) the following configuration files from [config/compute](/config/compute/etc/ceilometer)
   directory into `/etc/ceilometer`:

   ```
   pipeline.yaml
   ```

2. Restart Compute Agent.

   ```
   # service ceilometer-agent-compute restart
   ```


### Monasca

#### Monasca Ceilometer plugin

Please follow these steps to install in __all controller nodes__ the Python plugin and storage driver for Ceilometer to
send samples to Monasca:

1. Install python-monascaclient:

   ```
   # pip install python-monascaclient==1.0.27
   ```

2. Copy the following files from [Ceilosca][monasca_ceilometer_files] component (included in the latest release of
   [Monasca-Ceilometer][monasca_ceilometer]) into the Ceilometer package location `$PYTHON_SITE_PKG/ceilometer`:

   ```
   monasca_client.py
   storage/impl_monasca.py
   storage/impl_monasca_filtered.py
   publisher/monasca_data_filter.py
   publisher/monasca_metric_filter.py
   publisher/monclient.py
   ```

   Additionally, please create a text file at `$PYTHON_SITE_PKG/ceilometer-2015.1.*.egg-info` to record the exact
   version of Ceilosca being manually installed. For instance, when installing version "2015.1-FIWARE-5.3.3":

   ```
   # VERSION=2015.1-FIWARE-5.3.3
   # echo version=$VERSION > $PYTHON_SITE_PKG/ceilometer-2015.1.*.egg-info/ceilosca.txt
   ```

3. Edit the entry points file to add the following entries:

   At `[ceilometer.publisher]` section:
   ```
   monasca = ceilometer.publisher.monclient:MonascaPublisher
   ```

   At `[ceilometer.metering.storage]` section:
   ```
   monasca = ceilometer.storage.impl_monasca_filtered:Connection
   ```

4. Copy (or merge) the following configuration files from [config/controller](/config/controller/etc/ceilometer)
   directory into `/etc/ceilometer`:

   ```
   pipeline.yaml
   monasca_field_definitions.yaml
   ```

   Please ensure elements in __meter_source__ include the subset of Ceilometer metrics required by FIWARE Monitoring
   (this should be the case without any modifications) and don't forget to set *Monasca endpoint at Master Node* in
   the publishers of __meter_sink__:
   ```
   sinks:
       - name: meter_sink
         transformers:
         publishers:
             - notifier://
             - monasca://http://MONASCA_IP:8070/v2.0
   ```

5. Modify `/etc/ceilometer/ceilometer.conf` to configure a new meter storage driver for Ceilometer (*substitute with the
   endpoint of Master Node*):

   ```
   metering_connection = monasca://http://MONASCA_IP:8070/v2.0
   ```

   Please make sure the user specified under `[service_credentials]` section of the same file has __monasca_user__
   role added.

6. Restart all Ceilometer services:

   If using Fuel HA:
   ```
   # crm resource restart p_ceilometer-agent-central
   # crm resource restart p_ceilometer-alarm-evaluator
   # service ceilometer-agent-notification restart
   # service ceilometer-collector restart
   # service ceilometer-api restart
   # service ceilometer-alarm-notifier restart
   ```
   Otherwise:
   ```
   # CEILOMETER_SERVICES=$(cd /etc/init.d; ls -1 ceilometer*)
   # for NAME in $CEILOMETER_SERVICES; do service $NAME restart; done
   ```

#### Monasca Agent

In order to monitor the OpenStack services (i.e. __host services__), [monasca-agent][monasca_agent_doc] should be
installed in all the controllers:

1. Create a Python virtualenv located at `/opt/monasca`:

   ```
   # cd /opt
   # virtualenv monasca
   # source monasca/bin/activate
   ```

2. Please install `pbr` after upgrading your versions of `setuptools` and `pip`:

   ```
   (monasca)# pip install --upgrade setuptools
   (monasca)# pip install --upgrade pip
   (monasca)# pip install pbr==1.10.0
   (monasca)# pip install positional==1.1.0
   ```

3. Locate the [latest release][monasca_agent_releases] of Monasca Agent component and use `pip` tool to install it. For
   instance, to install version "1.1.21-FIWARE", please run:

   ```
   (monasca)# VERSION=1.1.21-FIWARE
   (monasca)# PBR_VERSION=$VERSION pip install git+https://github.com/telefonicaid/monasca-agent.git@$VERSION
   ```

4. Configure the component using `monasca-setup` (as described in the [documentation][monasca_agent_configuration]).
   Note that you will have to provide:

   * Your region name
   * The address or domain name of Monasca API
   * Valid Keystone credentials, usually those of the Ceilometer service (which should have previously been assigned
     the *monasca_user* role)

   ```
   (monasca)# monasca-setup \
     --username=YOUR_CEILOMETER_USER \
     --password=THE_PASSWORD \
     --project_name=service \
     --keystone_url=http://cloud.lab.fiware.org:4731/v3 \
     --monasca_url=http://MONASCA_IP:8070/v2.0 \
     --dimensions=region:YOUR_REGION
   ```

5. Only the file `process.yaml` used by [Process Checks plugin][monasca_agent_plugin_process_checks] is required at
   `/etc/monasca/agent/conf.d/`. Please ensure it is configured to monitor all OpenStack services (this should be the
   case without any modifications, but it is appropriate to check that all of your services are monitored). The example
   below shows configuration information for one service (nova-scheduler):

   ```
   - built_by: Nova
     detailed: false
     dimensions:
       component: nova-scheduler
       service: compute
     exact_match: false
     name: nova-scheduler
     search_string:
     - nova-scheduler
   ```

6. Please verify the configuration is correct:

   ```
   # service monasca-agent configtest
   ```

7. Finally, restart the agent:

   ```
   # service monasca-agent restart
   ```


## Verification

### Overall checks

In order to verify whether the installation and configuration of FIWARE Monitoring have been successful, we provide the
[fiware-check-monitoring.sh](/tools/fiware-check-monitoring.sh) script available at [tools](/tools) folder. It performs
a set of checks, not only in the controller itself but also in the compute nodes, and shows results in a human-readable
manner.

Running the script at the controllers with no additional parameters may suffice in most of the cases, although command
line options allow further adjustments. Script only requires defining the standard OpenStack environment variables with
the credentials needed to run `nova` and other commands.

For full information about the usage and options, please type: `fiware-check-monitoring.sh --help`

### Ceilometer queries

The former script will give us very comprehensive information about the installation and will also retrieve real metrics
and measurements to ensure FIWARE Monitoring is working properly. In any case, we could *optionally* try some queries
using the command line client of Ceilometer, like these:

*  Monitoring information about the region (please replace _RegionOne_ with yours):

   ```
   # ceilometer resource-list -q resource_id=RegionOne
   +-------------+-----------+---------+------------+
   | Resource ID | Source    | User ID | Project ID |
   +-------------+-----------+---------+------------+
   | RegionOne   | openstack | None    | None       |
   +-------------+-----------+---------+------------+
   ```

*  Monitoring information about one of your compute nodes (please note that the metric resource_id is the concatenation
   \<_host_\>\_\<_nodename_\>, values which are usually the same):

   ```
   # HOST_RESOURCE_ID=$(nova host-list | awk '/compute/ {print $2 "_" $2; exit}')
   # ceilometer meter-list -q resource_id=$HOST_RESOURCE_ID
   +--------------------------+-------+------+---------------------------+---------+------------+
   | Name                     | Type  | Unit | Resource ID               | User ID | Project ID |
   +--------------------------+-------+------+---------------------------+---------+------------+
   | compute.node.cpu.percent | gauge | %    | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.cpu.max     | gauge | cpu  | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.cpu.now     | gauge | cpu  | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.cpu.tot     | gauge | cpu  | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.disk.max    | gauge | GB   | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.disk.now    | gauge | GB   | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.disk.tot    | gauge | GB   | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.ram.max     | gauge | MB   | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.ram.now     | gauge | MB   | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.ram.tot     | gauge | MB   | node-2.aa.bb_node-2.aa.bb | None    | None       |
   +--------------------------+-------+------+---------------------------+---------+------------+
   ```

*  Monitoring information about one of your images:

   ```
   # IMAGE_NAME="base_centos_6"
   # IMAGE_RESOURCE_ID=$(nova image-show $IMAGE_NAME | awk '$2=="id" {print $4}')
   # ceilometer meter-list -q resource_id=$IMAGE_RESOURCE_ID
   +-------+-------+-------+--------------------------------------+---------+----------------------------------+
   | Name  | Type  | Unit  | Resource ID                          | User ID | Project ID                       |
   +-------+-------+-------+--------------------------------------+---------+----------------------------------+
   | image | gauge | image | 66d7c0ee-3929-4dbf-ac8e-39e17f44c445 | None    | 00000000000003228460960090160000 |
   +-------+-------+-------+--------------------------------------+---------+----------------------------------+
   ```

*  Monitoring information about one of the active instances:

   ```
   # INSTANCE_ID=$(nova list --all-tenants | awk '/ACTIVE/ {print $2; exit}')
   # ceilometer meter-list -q resource_id=$INSTANCE_ID
   +-----------------+-------+----------+--------------------------------------+----------+----------------------------------+
   | Name            | Type  | Unit     | Resource ID                          | User ID  | Project ID                       |
   +-----------------+-------+----------+--------------------------------------+----------+----------------------------------+
   | instance        | gauge | instance | 389190e8-6b55-4260-8b74-ee3a073e729d | somebody | 00000000000000000000000000004980 |
   | cpu_util        | gauge | %        | 389190e8-6b55-4260-8b74-ee3a073e729d | somebody | 00000000000000000000000000004980 |
   | disk.capacity   | gauge | B        | 389190e8-6b55-4260-8b74-ee3a073e729d | somebody | 00000000000000000000000000004980 |
   | disk.usage      | gauge | B        | 389190e8-6b55-4260-8b74-ee3a073e729d | somebody | 00000000000000000000000000004980 |
   | memory          | gauge | MB       | 389190e8-6b55-4260-8b74-ee3a073e729d | somebody | 00000000000000000000000000004980 |
   | memory.usage    | gauge | MB       | 389190e8-6b55-4260-8b74-ee3a073e729d | somebody | 00000000000000000000000000004980 |
   +-----------------+-------+----------+--------------------------------------+----------+----------------------------------+
   ```

   To query for the exact measurement values:
   ```
   # ceilometer sample-list -q resource_id=$INSTANCE_ID -m memory.usage --limit 3
   +--------------------------------------+--------------+-------+--------+------+---------------------------+
   | Resource ID                          | Name         | Type  | Volume | Unit | Timestamp                 |
   +--------------------------------------+--------------+-------+--------+------+---------------------------+
   | 389190e8-6b55-4260-8b74-ee3a073e729d | memory.usage | gauge | 140.0  | MB   | 2016-06-16T11:25:44+00:00 |
   | 389190e8-6b55-4260-8b74-ee3a073e729d | memory.usage | gauge | 140.0  | MB   | 2016-06-16T11:26:44+00:00 |
   | 389190e8-6b55-4260-8b74-ee3a073e729d | memory.usage | gauge | 140.0  | MB   | 2016-06-16T11:27:44+00:00 |
   +--------------------------------------+--------------+-------+--------+------+---------------------------+
   ```


[ceilometer]:
http://docs.openstack.org/developer/ceilometer/
"Ceilometer Developer Documentation"

[ceilometer_architecture_doc]:
http://docs.openstack.org/developer/ceilometer/architecture.html
"Ceilometer System Architecture"

[ceilometer_architecture_pict]:
http://docs.openstack.org/developer/ceilometer/_images/ceilo-arch.png
"Ceilometer System Architecture"

[telemetry]:
https://wiki.openstack.org/wiki/Telemetry
"OpenStack Telemetry"

[monasca]:
https://wiki.openstack.org/wiki/Monasca
"Monasca Documentation"

[monasca_agent_doc]:
https://github.com/telefonicaid/monasca-agent/blob/fiware/README.md
"Monasca Agent"

[monasca_agent_configuration]:
https://github.com/telefonicaid/monasca-agent/blob/fiware/docs/Agent.md#configuring
"Monasca Agent Configuration"

[monasca_agent_plugin_process_checks]:
https://github.com/telefonicaid/monasca-agent/blob/fiware/docs/Plugins.md#process-checks
"Monasca Agent Standard Plugins - Process Checks"

[monasca_agent_releases]:
https://github.com/telefonicaid/monasca-agent/releases
"Monasca Agent Releases"

[monasca_ceilometer]:
https://github.com/telefonicaid/monasca-ceilometer/tree/fiware
"Python plugin and storage driver for Ceilometer to send samples to Monasca"

[monasca_ceilometer_files]:
https://github.com/telefonicaid/monasca-ceilometer/tree/fiware/ceilosca/ceilometer
"Python plugin and storage driver for Ceilometer to send samples to Monasca"

[cosmos]:
https://github.com/Fiware/context.Cosmos/blob/master/README.md
"FIWARE Big Data GE (Cosmos)"

[fihealth_sanity_checks]:
https://github.com/Fiware/ops.Health/tree/master/fiware-region-sanity-tests
"FIWARE Health - Sanity Checks"

[fiware_lab_infographics]:
https://github.com/Fiware/ops.Fi-lab-infographics/blob/master/README.md
"FIWARE Lab Infographics"

[fiware_lab_monitoring_api]:
https://github.com/SmartInfrastructures/FIWARELab-monitoringAPI
"FIWARE Lab Monitoring API"

[fiware_monitoring_architecture_pict]:
/img/FIWARE_Monitoring_Arch.png
"FIWARE Monitoring Architecture"
