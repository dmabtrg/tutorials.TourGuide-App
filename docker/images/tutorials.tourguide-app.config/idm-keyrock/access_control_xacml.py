import logging
import json
import os
import argparse

os.environ['DJANGO_SETTINGS_MODULE'] = 'openstack_dashboard.settings'
from openstack_dashboard import settings
from openstack_dashboard import fiware_api

parser = argparse.ArgumentParser(description='Syncronice roles and permissions with Authzforce')
parser.add_argument('-f', '--file', help='Read data from <file>', required=True)
parser.add_argument('-d', '--domain', help='Set application <domain>', required=True)
args = parser.parse_args()

with open(args.file) as data_file:
    data = json.load(data_file)
app_id = data['id']

request=None
application = fiware_api.keystone.application_get(request, app_id)
application = fiware_api.keystone.application_update(
    request,
    application.id,
    ac_domain=args.domain)

role_permissions = {}
public_roles = [
    role for role in fiware_api.keystone.role_list(
        request, application=app_id)
    if role.is_internal == False
]

for role in public_roles:
    public_permissions = [
        perm for perm in fiware_api.keystone.permission_list(
        request, role=role.id)
        if perm.is_internal == False
    ]
    if public_permissions:
        role_permissions[role.id] = public_permissions

fiware_api.access_control_ge.policyset_update(
    request,
    application=application,
    role_permissions=role_permissions)
