{% if grains['os_family'] == 'RedHat' %}
env_dir: /etc/sysconfig
{% else %}
env_dir: /etc/default
{% endif %}
