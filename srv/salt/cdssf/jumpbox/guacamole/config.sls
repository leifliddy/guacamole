# vim: tabstop=2 expandtab shiftwidth=2 softtabstop=2

# enter short or long hostnames of systems that will need guacamole ssh + rdp connections created
{% set guac_connections = pillar['jumpbox']['guac_connections'] %}


change_default_guacadmin_password:
  module.run:
    - guac.change_default_guacadmin_password:

create_guac_user_group:
  module.run:
    - guac.create_group:
      - guac_user_group: cdssf

{% for hostname in guac_connections %}
create_{{ hostname }}_rdp_connection:
  module.run:
    - guac.create_rdp_connection:
      - rdp_connection_name: {{ hostname }}-rdp
      - hostname: {{ hostname }}

create_{{ hostname }}_ssh_connection:
  module.run:
    - guac.create_ssh_connection:
      - ssh_connection_name: {{ hostname }}-ssh
      - hostname: {{ hostname }}

add_{{ hostname }}_rdp_connection_to_guac_group:
  module.run:
    - guac.add_connection_to_group:
      - connection_name: {{ hostname }}-rdp
      - guac_user_group: cdssf

add_{{ hostname }}_ssh_connection_to_guac_group:
  module.run:
    - guac.add_connection_to_group:
      - connection_name: {{ hostname }}-ssh
      - guac_user_group: cdssf
{% endfor %}
