#!/bin/bash
crm resource restart p_ceilometer-agent-central
crm resource restart p_ceilometer-alarm-evaluator
service ceilometer-agent-notification restart
service ceilometer-collector restart
service ceilometer-alarm-notifier restart
service ceilometer-api restart
