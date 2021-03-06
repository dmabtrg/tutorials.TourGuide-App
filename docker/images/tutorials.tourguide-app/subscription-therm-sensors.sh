#!/bin/bash
# subscription-therm-sensors.sh
# Copyright(c) 2016 Bitergia
# Author: Alvaro del Castillo <acs@bitergia.com>,
# David Muriel <dmuriel@bitergia.com>
# MIT Licensed
#
# IDAS temperature sensors used in restaurants

TOURGUIDE_HOST=$( hostname -i )
TOURGUIDE_URL=http://${TOURGUIDE_HOST}/api/sensors/
ORION_URL=http://${ORION_NO_PROXY_HOSTNAME}:${ORION_PORT}/v1/subscribeContext

cat <<EOF | curl ${ORION_URL} -s -S --header 'Content-Type: application/json' --header 'Accept: application/json' --header 'Fiware-Service: tourguideidas' --header 'Fiware-ServicePath: /' -d @-
{
    "entities": [
        {
            "type": "thing",
            "isPattern": "true",
            "id": "SENSOR_TEMP_.*"
        }
    ],
    "attributes": [
        "temperature"
    ],
    "reference": "${TOURGUIDE_URL}",
    "duration": "P1M",
    "notifyConditions": [
        {
            "type": "ONCHANGE",
            "condValues": [
                "TimeInstant"
            ]
        }
    ]
}
EOF
