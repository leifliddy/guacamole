# vim: tabstop=2 expandtab shiftwidth=2 softtabstop=2

{% set guacamole_svc_acct         = 'guacamole_svc_acct' %}
{% set guacamole_svc_acct_pass    = pillar['jumpbox']['guacamole_svc_acct_pass'] %}
{% set guacamole_version          = pillar['jumpbox']['guacamole_version'] %}
{% set guacamole_user_db_password = pillar['jumpbox']['guacamole_user_db_password'] %}
{% set guac_json                  = pillar['jumpbox']['guac_json'] %}
{% set guac_logo                  = pillar['jumpbox']['guac_logo'] %}
{% set ipa_domain                 = pillar['jumpbox']['ipa_domain'] %}
{% set tomcat_ajp                 = { 'port' : pillar['ports']['jumpbox']['tomcat_ajp']['number'],
                                      'type' : pillar['ports']['jumpbox']['tomcat_ajp']['type'] } %}
{% set tomcat_http                = { 'port' : pillar['ports']['jumpbox']['tomcat_http']['number'],
                                      'type' : pillar['ports']['jumpbox']['tomcat_http']['type'] } %}
{% set tomcat_https               = { 'port' : pillar['ports']['jumpbox']['tomcat_https']['number'],
                                       'type' : pillar['ports']['jumpbox']['tomcat_https']['type'] } %}
{% set tomcat_shutdown            = { 'port' : pillar['ports']['jumpbox']['tomcat_shutdown']['number'],
                                       'type' : pillar['ports']['jumpbox']['tomcat_shutdown']['type'] } %}
{% set guacd_port                 = pillar['ports']['jumpbox']['guacd']['number'] %}
{% set mysql_port                 = pillar['dit']['mysql_port'] %}
{% set ldap_port                  = pillar['ports']['ldap']['ldap']['number'] %}


ipa_add_guacamole_group:
    module.run:
    - ipa.add_group:
      - group_name: guacamole

create_guacamole_svc_account:
  module.run:
    - ipa.add_svc_acct:
        - svc_acct_name: {{ guacamole_svc_acct }}
        - password:      {{ guacamole_svc_acct_pass }}

{% for guac_dir in ['extensions','lib'] %}
setup_guac_{{ guac_dir }}:
  file.recurse:
    - name:           /etc/guacamole/{{ guac_dir }}
    - source:         salt://_resource/archive/guacamole/{{ guac_dir }}
    - user:           root
    - group:          root
    - file_mode:      '0644'
    - dir_mode:       '0755'
    - include_empty:  True
{% endfor %}

deploy_guacd_conf:
  file.managed:
    - name:          /etc/guacamole/guacd.conf
    - source:        salt://cdssf/jumpbox/guacamole/files/guacd.conf.jinja
    - template:      jinja
    - user:          root
    - group:         root
    - mode:          '0644'
    - makedirs:      True
    - defaults:
        guacd_port:  {{ guacd_port }}

deploy_guacamole_properties:
  file.managed:
    - name:          /etc/guacamole/guacamole.properties
    - source:        salt://cdssf/jumpbox/guacamole/files/guacamole.properties.jinja
    - template:      jinja
    - user:          root
    - group:         tomcat
    - mode:          '0640'
    - defaults:
        password:       '{{ guacamole_user_db_password }}'
        domain:         {{ ipa_domain }}
        mysql_port:     {{ mysql_port }}
        ldap_port:      {{ ldap_port }}
        svc_acct:       {{ guacamole_svc_acct }}
        svc_acct_pass:  '{{ guacamole_svc_acct_pass }}'

install_guacamole_client:
  file.managed:
    - name:     /var/lib/tomcat/webapps/guacamole.war
    - source:   salt://_resource/archive/guacamole/guacamole-{{ guacamole_version }}.war
    - user:     tomcat
    - group:    tomcat
    - mode:     '0644'

backup_tomcat_server_xml:
  file.copy:
    - name:     /etc/tomcat/server.xml.orig
    - source:   /etc/tomcat/server.xml
    - preserve: True
    - unless:   rpm tomcat --verify | grep -q /etc/tomcat/server.xml

deploy_tomcat_server_xml:
  file.managed:
    - name:          /etc/tomcat/server.xml
    - source:        salt://cdssf/jumpbox/guacamole/files/server.xml.jinja
    - template:      jinja
    - user:          root
    - group:         tomcat
    - mode:          '0644'
    - defaults:
        ajp_port:       {{ tomcat_ajp.port }}
        http_port:      {{ tomcat_http.port }}
        https_port:     {{ tomcat_https.port }}
        shutdown_port:  {{ tomcat_shutdown.port }}

set_tomcat_selinux_boolean:
  selinux.boolean:
    - name:     tomcat_can_network_connect_db
    - value:    True
    - persist:  True

{% for tomcat in [tomcat_ajp, tomcat_http,tomcat_https, tomcat_shutdown] %}
add_selinux_port_{{ tomcat.port }}:
  selinux.port_policy_present:
    - name:     tcp/{{ tomcat.port }}
    - sel_type: {{ tomcat.type }}
{% endfor %}

modify_httpd_nss_conf:
  file.line:
    - name:     /etc/httpd/conf.d/nss.conf
    - mode:     ensure
    - after:    Include /etc/httpd/conf.d/ipa-rewrite.conf
    - content:  Include /etc/httpd/conf.d/guacamole.conf
    - unless:   grep -q 'Include /etc/httpd/conf.d/guacamole.conf' /etc/httpd/conf.d/nss.conf

deploy_httpd_reverse_proxy_conf:
  file.managed:
    - name:     /etc/httpd/conf.d/guacamole.conf
    - source:   salt://cdssf/jumpbox/guacamole/files/httpd-guacamole.conf.jinja
    - template: jinja
    - user:     root
    - group:    root
    - mode:     '0644'
    - defaults:
        http_port: {{ tomcat_http.port }}

start_enable_guacd_service:
  service.running:
    - name:   guacd
    - enable: True
    - watch:
      - setup_guac_extensions
      - setup_guac_lib
      - deploy_guacd_conf
      - deploy_guacamole_properties

start_enable_tomcat_service_1:
  service.running:
    - name:       tomcat
    - enable:     True
    - init_delay: 5
    - watch:
      - install_guacamole_client

reload_httpd_service:
  service.running:
    - name:   httpd
    - reload: True
    - watch:
      - modify_httpd_nss_conf
      - deploy_httpd_reverse_proxy_conf

modify_login_text:
  file.line:
    - name:    {{ guac_json }}
    - mode:    replace
    - content: '"NAME"    : "Jumpbox",'
    - match:   '"NAME"    : "Apache Guacamole",$'

backup_guac-tricolor_logo:
  file.copy:
    - name:     {{ guac_logo }}.orig
    - source:   {{ guac_logo }}
    - preserve: True
    - unless:   test -f {{ guac_logo }}.orig

deploy_new_logo:
  file.managed:
    - name:     {{ guac_logo }}
    - source:   salt://_resource/archive/guacamole/logo/framework_logo_black.png
    - user:     tomcat
    - group:    tomcat
    - mode:     '0644'

start_enable_tomcat_service_2:
  service.running:
    - name:   tomcat
    - enable: True
    - watch:
      - modify_login_text
      - deploy_new_logo
