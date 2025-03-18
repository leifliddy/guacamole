# vim: tabstop=2 expandtab shiftwidth=2 softtabstop=2

{% set interface      = pillar['system']['nic_oob_admin'] %}


start_enable_firewalld_service:
  service.running:
    - name:   firewalld
    - enable: True

configure_firewalld_zone:
  firewalld.present:
    - name:           public
    - prune_services: True
    - services:
      - ssh
    - interfaces:
      - {{ interface }}
