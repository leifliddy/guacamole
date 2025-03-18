# vim: tabstop=2 expandtab shiftwidth=2 softtabstop=2

{% set backup_files = ['/etc/xrdp/sesman.ini'] %}


stop_disable_xrdp_service:
  service.dead:
    - name:   xrdp
    - enable: False

{% for xrdp_file in backup_files %}
restore_{{ xrdp_file }}:
  file.copy:
    - name:     {{ xrdp_file }}
    - source:   {{ xrdp_file }}.orig
    - preserve: True
    - onlyif: test -f {{ xrdp_file }}.orig
{% endfor %}

firewalld_remove_service_rdp:
  module.run:
    - firewalld.remove_service:
      - service: rdp
      - zone: public
      - permanent: true

# make permanent rules the new runtime rules
firewalld_reload_rules:
  module.run:
    - firewalld.reload_rules:
