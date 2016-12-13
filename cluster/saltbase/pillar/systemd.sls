is_systemd: True
{% if grains['os_family'] == 'RedHat' %}
systemd_system_path: /usr/lib/systemd/system
{% else %}
systemd_system_path: /lib/systemd/system
{% endif %}
