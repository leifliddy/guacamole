# vim: tabstop=4 expandtab shiftwidth=4 softtabstop=4

import guacapy
import guacapy.templates as template
import logging
import pymysql
import sys

__virtualname__ = 'guac'

log = logging.getLogger(__name__)


def _group_does_not_exist(guac_user_group):
    group_list = list_groups()

    if guac_user_group not in group_list:
        log.error('the guacmole group: ' + guac_user_group + ' does not exist')
        return True

    return False


def _group_exists(guac_user_group):
    group_list = list_groups()

    if guac_user_group in group_list:
        log.warning('the guacmole user group: ' + guac_user_group + ' already exists')
        return True

    return False


def _user_does_not_exist(guac_user):
    user_list = list_users()

    if guac_user not in user_list:
        log.warning('the guacmole user: ' + guac_user + ' does not exist')
        return True

    return False


def _user_exists(guac_user):
    user_list = list_users()

    if guac_user in user_list:
        log.warning('the guacmole user: ' + guac_user + ' already exists')
        return True

    return False


def _establish_connection(default_pass=False):
    hostname          = __grains__['fqdn']
    guac_url          = hostname + '/guacamole'
    guac_admin_user   = __pillar__['jumpbox']['guac_admin_user']
    guac_admin_passwd = __pillar__['jumpbox']['guac_admin_password']
    cert_path         = '/etc/ipa/ca.crt'

    # this is used when changing the default 'guacadmin' password to guac_admin_passwd
    if default_pass:
        guac_admin_passwd = 'guacadmin'

    try:
        client = guacapy.Guacamole(guac_url,
                                   guac_admin_user,
                                   guac_admin_passwd,
                                   default_datasource='mysql',
                                   method='https',
                                   verify=cert_path)
    except Exception as e:
        msg = e.args
        log.error(msg)
        if default_pass:
            log.error('ERROR establishing connection - the default guacadmin password might already be changed')
            return False
        log.error('ERROR establishing connection')
        sys.exit(1)

    return client


def _establish_db_connection():
    db_host = 'localhost'
    db_user = 'root'
    db_pass = __pillar__['mysql']['server']['root_password']
    db_name = 'guacamole_db'

    try:
        db = pymysql.connect(host=db_host,
                             user=db_user,
                             password=db_pass,
                             database=db_name,
                             charset='utf8mb4',
                             cursorclass=pymysql.cursors.DictCursor)
    except Exception as e:
        code,msg = e.args
        log.error('Error code ' + str(code) + ': ' + msg)
        log.error('ERROR establishing mariadb connection')
        sys.exit(1)

    return db


def _get_connection_id(connection_name):
    client = _establish_connection()
    connection_details = client.get_connection_by_name(connection_name)

    if connection_details:
        return connection_details['identifier']
    else:
        return False


def _parse_sql_file(sql_file):
    sql_data = open(sql_file, 'r').readlines()
    stmt_list = []
    delimiter = ';'
    stmt = ''

    for linenum, line in enumerate(sql_data):
        if not line.strip():
            continue

        if line.lstrip().startswith('--'):
            continue

        if delimiter not in line:
            stmt += line
            continue

        if stmt:
            stmt += line
            stmt_list.append(stmt.strip())
            stmt = ''
        else:
            stmt_list.append(line.strip())

    return stmt_list


def db_apply_schema(sql_file):
    db = _establish_db_connection()
    sql_file = __salt__['cp.cache_file'](sql_file)
    stmt_list = _parse_sql_file(sql_file)

    try:
        with db.cursor() as cursor:
            for stmt in stmt_list:
                cursor.execute(stmt)
            db.commit()
    except Exception as e:
        code,msg = e.args
        log.error('Error code ' + str(code) + ': ' + msg)
        if code == 1050:
            log.error('This signifies that the guacamole_db schema has already been created\n')
            return True
        if code == 1062:
            log.error(msg)
            log.error('This signifies that the guacadmin user has already been created\n')
            return True
        return False

    return True


# this changes the default 'guacadmin' password to the guac_admin_passwd
# this function won't do anything if the default password has already been changed
def change_default_guacadmin_password():
    client = _establish_connection(default_pass=True)

    if not client:
        return True

    guac_admin_user = 'guacadmin'
    guac_admin_passwd = __pillar__['jumpbox']['guac_admin_password']

    user_payload = {'password': guac_admin_passwd,
                    'attributes':{}}

    client.edit_user(guac_admin_user, user_payload)

    return True


def check_connection_exists(connection_name):
    client = _establish_connection()
    connection_details = client.get_connection_by_name(connection_name)

    if connection_details:
        return True
    else:
        return False


def create_rdp_connection(rdp_connection_name, hostname='localhost'):
    client = _establish_connection()
    rdp_connection_exists = check_connection_exists(rdp_connection_name)

    if rdp_connection_exists:
        log.warning('connection: ' + rdp_connection_name + ' already exists')
        return True

    rdp_connection = template.RDP_CONNECTION

    rdp_connection['name'] = rdp_connection_name
    rdp_connection['parameters']['hostname'] = hostname
    rdp_connection['parameters']['security'] = 'tls'
    rdp_connection['parameters']['disable-audio'] = True
    rdp_connection['parameters']['ignore-cert'] = True
    rdp_connection['parameters']['username'] = '${GUAC_USERNAME}'
    rdp_connection['parameters']['password'] = '${GUAC_PASSWORD}'

    client.add_connection(rdp_connection)

    return True


def create_ssh_connection(ssh_connection_name, hostname='localhost'):
    client = _establish_connection()
    ssh_connection_exists = check_connection_exists(ssh_connection_name)

    if ssh_connection_exists:
        log.warning('connection: ' + ssh_connection_name + ' already exists')
        return True

    ssh_connection = template.SSH_CONNECTION

    ssh_connection['name'] = ssh_connection_name
    ssh_connection['parameters']['hostname'] = hostname
    ssh_connection['parameters']['username'] = '${GUAC_USERNAME}'
    ssh_connection['parameters']['password'] = '${GUAC_PASSWORD}'

    client.add_connection(ssh_connection)

    return True


def delete_connection(connection_name):
    client = _establish_connection()
    connection_id = _get_connection_id(connection_name)

    if not connection_id:
        log.error('connection: ' + connection_name + ' does not exist')
        return True

    client.delete_connection(connection_id)

    return True


def list_groups():
    client = _establish_connection()
    group_list = []

    all_groups = client.get_user_groups()

    for group in all_groups.keys():
        group_list.append(group)

    return sorted(group_list)


def create_group(guac_user_group='cdssf'):
    client = _establish_connection()

    group_payload = {'identifier': guac_user_group,
                     'attributes': {
                         'disabled': ''}}

    if _group_exists(guac_user_group):
        return True

    client.add_group(group_payload)

    return True


def delete_group(guac_group):
    client = _establish_connection()

    if _group_does_not_exist(guac_group):
        return True

    client.delete_group(guac_group)

    return True


def add_connection_to_group(connection_name, guac_user_group='cdssf'):
    client = _establish_connection()
    connection_id = _get_connection_id(connection_name)

    if not connection_id:
        log.error('connection: ' + connection_name + ' does not exist')
        return

    if _group_does_not_exist(guac_user_group):
        return True

    connection_payload = [
        {'op': 'add', 'path': '/connectionPermissions/' + connection_id, 'value': 'READ'}]

    client.grant_group_permission(guac_user_group, connection_payload)

    return True


def list_users():
    client = _establish_connection()
    user_list = []

    all_users = client.get_users()

    for user in all_users.keys():
        user_list.append(user)

    return sorted(user_list)


def list_members(guac_user_group='cdssf'):
    client = _establish_connection()
    member_list = []

    if _group_does_not_exist(guac_user_group):
        return True

    member_list = client.get_group_members(guac_user_group)

    if  member_list:
        member_list.sort()
        print('\n' + '\n'.join(member_list) + '\n')
    else:
        log.error('the guacmole group: ' + guac_user_group + ' has no members')

    return True


def add_user(guac_user):
    client = _establish_connection()

    if _user_exists(guac_user):
        return True

    else:
        user_payload = {'username': guac_user,
                        'attributes': {
                            'disabled': ''}}

        client.add_user(user_payload)

    return True


# auto-create the user and group if they don't exist
def add_user_to_group(user, guac_user_group='cdssf'):
    client = _establish_connection()

    # if group doesn't exist, group will be added to guacamole

    if _group_does_not_exist(guac_user_group):
        create_group(guac_user_group)

    # if user doesn't exist, user will be added to guacamole
    if _user_does_not_exist(user):
        add_user(user)

    group_membership_payload = [{'op': 'add', 'path': '/', 'value': user}]

    client.edit_group_members(guac_user_group, group_membership_payload)

    return True


def delete_user(guac_user):
    client = _establish_connection()

    if _user_exists(guac_user):
        return True

    client.delete_user(guac_user)

    return True
