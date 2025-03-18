# vim: tabstop=2 expandtab shiftwidth=2 softtabstop=2

{% set rdp_port     = pillar['ports']['jumpbox']['rdp']['number'] %}
{% set rdp_protocol = pillar['ports']['jumpbox']['rdp']['protocol'] %}
{% set backup_files = ['/etc/xrdp/sesman.ini'] %}


{% for xrdp_file in backup_files %}
backup_{{ xrdp_file }}:
  file.copy:
    - name:     {{ xrdp_file }}.orig
    - source:   {{ xrdp_file }}
    - preserve: True
    - unless: rpm xrdp --verify | grep -q {{ xrdp_file }}
{% endfor %}

deploy_desktop_config:
  file.managed:
    - name:      /etc/sysconfig/desktop
    - source:    salt://cdssf/jumpbox/xrdp/conf/desktop
    - user:      root
    - group:     root
    - mode:      '0644'

disable_fuse_mount:
  file.uncomment:
    - name: /etc/xrdp/sesman.ini
    - regex: EnableFuseMount=false

comment_out_pulse_variable:
  file.comment:
    - name: /etc/xrdp/sesman.ini
    - regex: ^PULSE_SCRIPT

start_enable_xrdp_service:
  service.running:
    - name: xrdp
    - enable: True
    - watch:
      - disable_fuse_mount

create_firewalld_rdp_service:
  firewalld.service:
    - name: rdp
    - ports:
      - {{ rdp_port }}/{{ rdp_protocol }}

# not needed if running one jumpbox system since guacamole is only accessing this port locally
# however, this is needed for guacamole to access any (external) jumpbox client systems
# should probably devise a way to seperate out the jumpbox master + client systems
# or to only allow the src ip of the jumpbox master system to access this port
add_rdp_service_to_public_zone:
  firewalld.present:
    - name: public
    - services:
      - rdp
