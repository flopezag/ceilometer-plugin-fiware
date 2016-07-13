import pbr.version
import logging

class UnSupportedComponent(Exception):
	def __init__(self, value):
		self.value = value
	def __str__(self):
		return "Unsupported Component Version: " + repr(self.value)


class OpenStackComponentVersionManager():

	#Supported components
	NOVA = "nova"
	CINDER = "cinder"
	NEUTRON = "neutron"
	GLANCE = "glance"
	KEYSTONE = "keystone"
	CEILOMETER = "ceilometer"


	#internal names to gather the OpenStack version (usually they are the same, but with this approach, we can decouple the internal name)
	_NOVA_INT = "nova"
	_CINDER_INT = "cinder"
	_NEUTRON_INT = "neutron"
	_GLANCE_INT = "glance"
	_KEYSTONE_INT = "keystone"
	_CEILOMETER_INT = "ceilometer"


	##common method to know the version
	##if some of the component needs a special call, we will need to introduce the specific action in the appropiated method. 
	def _get_component_version_common(self, component):
		if logging.getLogger().isEnabledFor(logging.DEBUG):
			logging.debug("_get_component_version_common(): for " + component)
		
		try:
			versionInfo = pbr.version.VersionInfo(component)
			versionInfoStr = versionInfo.version_string()
		except Exception, e:
			#we manage the exception, since it means that the OpenStack component is not installed.
			#Typically the exception is:"raise Exception("Versioning for this project requires either an sdist"
			#		Exception: Versioning for this project requires either an sdist tarball, or access to  
			#		an upstream git repository. Are you sure that git is installed?"
			if logging.getLogger().isEnabledFor(logging.DEBUG):
				logging.debug ("_get_component_version_common(): Exception Detail - " + str(e))
			logging.warning ("_get_component_version_common(): Error collecting "+ component + " version; to be reviewed the component version in this server")
			versionInfoStr = None
		return versionInfoStr

	##internal method to validate if the name of the component is valid.
	def _is_valid_component(self, component_name):
		#low performance in a big list, for us it is enough
		return component_name in self.get_list_valid_components()


	##specific method to obtain the nova version. We have decouple the name and the name of the method, in order to be sure that if something change we could manage in a easy way.
	def get_component_version_nova(self):
		return self._get_component_version_common(self._NOVA_INT)

	##specific method to obtain the cinder version. We have decouple the name and the name of the method, in order to be sure that if something change we could manage in a easy way.
	def get_component_version_cinder(self):
		return self._get_component_version_common(self._CINDER_INT)

	##specific method to obtain the neutron version. We have decouple the name and the name of the method, in order to be sure that if something change we could manage in a easy way.
	def get_component_version_neutron(self):
		return self._get_component_version_common(self._NEUTRON_INT)

	##specific method to obtain the glance version. We have decouple the name and the name of the method, in order to be sure that if something change we could manage in a easy way.
	def get_component_version_glance(self):
		return self._get_component_version_common(self._GLANCE_INT)

	##specific method to obtain the keystone version. We have decouple the name and the name of the method, in order to be sure that if something change we could manage in a easy way.
	def get_component_version_keystone(self):
		return self._get_component_version_common(self._KEYSTONE_INT)

	##specific method to obtain the keystone version. We have decouple the name and the name of the method, in order to be sure that if something change we could manage in a easy way.
	def get_component_version_ceilometer(self):
		return self._get_component_version_common(self._CEILOMETER_INT)

	##Method to obtain the component version
	##attibutes: 
	##**component: name of the component that we know the version. Domanin: CalendarSynchronizer.NOVA, CalendarSynchronizer.CINDER.....

	def get_list_valid_components(self):
		return [self.NOVA, self.CINDER, self.NEUTRON, self.GLANCE, self.KEYSTONE, self.CEILOMETER]

	def get_component_version(self, component):
		#validate if the name of the component is valid, if not we will raise an exception. 
		#The name should be aligned in the development phase and it should not be dinamic.
		if not self._is_valid_component(component):
			logging.error ("get_component_version(): UnSupportedComponent exception for the component: " + component)
			raise UnSupportedComponent(component)

		#if it is correct, we will obtain the version of the component
		version_value = None

		#Call dynamically the appropriate method
		name_component_method = "get_component_version_" + component
		#to call directly the method of the script file
		#version_value = globals()[name_component_method]()
		#in our case, we want to call the method of our class
		func = getattr(self, name_component_method)
		version_value = func()

		#initialization of the component detail
		component_attibute = {"component": component, "isInstalled": False}
		if version_value is not None:
			component_attibute["isInstalled"] = True
			attibutes = {'attibutes':{'version': version_value}}
			component_attibute.update(attibutes)
		return component_attibute


	##Method to obtain a list of components version and add the element into the array.
	##attibutes: 
	##**component_list: list of name of the component that we know the version. Domanin of values: CalendarSynchronizer.NOVA, CalendarSynchronizer.CINDER.....
	def get_components_version(self, component_list):
		components_array = []
		for component_name in component_list:
			component_element = self.get_component_version(component_name)
			if logging.getLogger().isEnabledFor(logging.INFO):
				logging.info("get_components_version(): Component description: " + str(component_element))
			components_array.append(component_element)
		if logging.getLogger().isEnabledFor(logging.INFO):
			logging.info("get_components_version(): List of components: " + str(components_array))
		return components_array

	##Method to obtain all the supported components version and add the element into the array.
	def get_all_components_version(self):
		component_list = self.get_list_valid_components()
		return self.get_components_version(component_list)


if __name__ == '__main__':
	logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
	manager = OpenStackComponentVersionManager()
	
	#example how to obtain all the components
	logging.info("#######################")
	logging.info("#####All the components")
	component_version = manager.get_all_components_version()
	logging.info("#####RESULTS:")
	logging.info("#####  Version of all the components: " + str(component_version))
	logging.info("#######################")

	logging.info("")
	logging.info("")
	#example how to obtain some of the components
	logging.info("#######################")
	logging.info("#####Some of the components, for example CINDER and NEUTRON")
	components = [manager.CINDER, manager.NEUTRON]
	component_version = manager.get_components_version(components)
	logging.info("#####RESULTS:")
	logging.info("#####  Version of  CINDER and NEUTRON: " + str(component_version))
	logging.info("#######################")

	logging.info("")
	logging.info("")
	#example how to obtain only one components
	logging.info("#######################")
	logging.info("#####Only one component, for example GLANCE")
	component_version = manager.get_component_version_glance()
	logging.info("#####RESULTS:")
	logging.info("#####  Version of  GLANCE: " + str(component_version))

