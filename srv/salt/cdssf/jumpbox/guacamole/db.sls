# vim: tabstop=2 expandtab shiftwidth=2 softtabstop=2

{% set mariadb_root_password = pillar['mysql']['server']['root_password'] %}
{% set guacamole_user_db_password = pillar['jumpbox']['guacamole_user_db_password'] %}
{% set guac_sql_files = ['001-create-schema.sql', '002-create-admin-user.sql'] %}


install_mariadb-server:
  pkg.installed:
    - name: mariadb-server

start_enable_mariadb_service:
  service.running:
    - name:       mariadb
    - enable:     True
    - init_delay: 3
    - require:
      - install_mariadb-server

set_mariadb_root_password:
  mysql_user.present:
    - name:               root
    - host:               localhost
    - password:           '{{ mariadb_root_password }}'
    - connection_charset: utf8
    - saltenv:
      - LC_ALL: 'en_US.utf8'
    - require:
      - start_enable_mariadb_service

create_guacamole_db:
  mysql_database.present:
    - name:            guacamole_db
    - connection_host: localhost
    - connection_user: root
    - connection_pass: '{{ mariadb_root_password }}'
    - require:
      - set_mariadb_root_password

create_guacamole_db_user:
  mysql_user.present:
    - name:     guacamole_user
    - host:     localhost
    - password: '{{ guacamole_user_db_password }}'
    - use:
      - mysql_database: create_guacamole_db
    - require:
      - create_guacamole_db

guacamole_db_user_grant_perms:
   mysql_grants.present:
    - user:     guacamole_user
    - host:     localhost
    - grant:    select,insert,update,delete
    - database: guacamole_db.*
    - use:
      - mysql_database: create_guacamole_db
    - require:
      - create_guacamole_db_user

{% for sql_file in guac_sql_files %}
guacamole_db_import_{{ sql_file }}:
  module.run:
    - guac.db_apply_schema:
      - sql_file: salt://_resource/archive/guacamole/schema/{{ sql_file }}
    - require:
      - guacamole_db_user_grant_perms
{% endfor %}
