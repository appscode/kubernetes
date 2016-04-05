{% set etcd_host = "" -%}
{% set strongswan_manifest = "" -%}
{% if grains['roles'][0] == 'kubernetes-master' -%}
  {% set etcd_host = grains.internal_ip -%}
  {% set strongswan_manifest = "strongswan-master.manifest" -%}
{% elif grains['roles'][0] == 'kubernetes-pool' -%}
  {% set etcd_host = grains.api_servers -%}
  {% set strongswan_manifest = "strongswan-node.manifest" -%}
{% endif -%}

/etc/kubernetes/manifests/strongswan-h2h-psk.manifest:
  file.managed:
    - source: salt://strongswan-h2h-psk/{{strongswan_manifest}}
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true
    - dir_mode: 755
    - context:
        fqdn: {{ grains['id'] }}
        internal_ip: {{ grains.internal_ip }}
        etcd_host: {{ etcd_host }}
        etcd_port: 4004
        etcd_peer_port: 2383
        cpulimit: '"100m"'
        vpn_psk: {{ pillar['vpn_psk'] }}
    - require:
      - service: docker
