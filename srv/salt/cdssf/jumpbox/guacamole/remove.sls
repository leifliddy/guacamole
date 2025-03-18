# vim: tabstop=2 expandtab shiftwidth=2 softtabstop=2

{% set guac_del_list = ['/etc/guacamole', '/etc/httpd/conf.d/guacamole.conf', '/var/lib/tomcat/webapps/guacamole', '/var/lib/tomcat/webapps/guacamole.war'] %}
{% set service_list = ['guacd', 'mariadb', 'tomcat'] %}


{% for service in service_list %}
stop_disable_{{ service }}_service:
  service.dead:
    - name:   {{ service }}
    - enable: False
{% endfor %}

clear_contents_of_var_lib_mysql:
  cmd.run:
    - name:   rm -rf /var/lib/mysql/*
    - onlyif: test -d /var/lib/mysql

{% for guac_file_dir in guac_del_list %}
remove_{{ guac_file_dir }}:
  file.absent:
    - name: {{ guac_file_dir }}
{% endfor %}

restore_tomcat_server_xml:
  file.copy:
    - name:     /etc/tomcat/server.xml
    - source:   /etc/tomcat/server.xml.orig
    - preserve: True
    - onlyif:   test -f /etc/tomcat/server.xml.orig

modify_httpd_nss_conf:
  file.line:
    - name:   /etc/httpd/conf.d/nss.conf
    - mode:   delete
    - match:  Include /etc/httpd/conf.d/guacamole.conf
    - onlyif: test -f /etc/httpd/conf.d/nss.conf

reload_httpd_service:
  service.running:
    - name:   httpd
    - reload: True
    - watch:
      - modify_httpd_nss_conf
