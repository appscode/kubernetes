include:
  - docker
  - kubelet

{% set etcd_host = "" -%}
{% set calico_manifest = "" -%}
{% if grains['roles'][0] == 'kubernetes-master' -%}
  {% set etcd_host = grains.internal_ip -%}
  {% set calico_manifest = "calico-master.manifest" -%}
{% elif grains['roles'][0] == 'kubernetes-pool' -%}
  {% set etcd_host = grains.api_servers -%}
  {% set calico_manifest = "calico-node.manifest" -%}
{% endif -%}

/usr/bin/calicoctl:
  file.managed:
    - source: https://github.com/projectcalico/calico-containers/releases/download/v0.18.0/calicoctl
    - source_hash: sha1=1b97aaf37b60d5f90c32a280c1f27d3fb9484801
    - user: root
    - group: root
    - mode: 755
    - makedirs: true
    - dir_mode: 755
    - require_in:
      - service: kubelet

/opt/cni/bin/calico:
  file.managed:
    - source: https://github.com/projectcalico/calico-cni/releases/download/v1.1.0/calico
    - source_hash: sha1=b8dcacbfa3480640fd971e8f188950452f68b08a
    - user: root
    - group: root
    - mode: 755
    - makedirs: true
    - dir_mode: 755
    - require_in:
      - service: kubelet

/opt/cni/bin/calico-ipam:
  file.managed:
    - source: https://github.com/projectcalico/calico-cni/releases/download/v1.1.0/calico-ipam
    - source_hash: sha1=f2ef440f1a4ba339350b6d18af7477a388a9bd27
    - user: root
    - group: root
    - mode: 755
    - makedirs: true
    - dir_mode: 755
    - require_in:
      - service: kubelet

/etc/cni/net.d/10-calico.conf:
  file.managed:
    - source: salt://calico/calico.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true
    - dir_mode: 755
    - context:
        kubernetes_master_name: {{ pillar['kubernetes_master_name'] }}
        etcd_host: {{ etcd_host }}
        etcd_port: 4003
    - require_in:
      - service: kubelet

/var/run/calico:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - file_mode: 644
    - recurse:
        - user
        - group
        - mode

/var/log/calico:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 755
    - file_mode: 644
    - recurse:
        - user
        - group
        - mode

{% if grains['roles'][0] == 'kubernetes-master' %}

/etc/kubernetes/manifests/calico-etcd.manifest:
  file.managed:
    - source: salt://calico/calico-etcd.manifest
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true
    - dir_mode: 755
    - context:
        etcd_host: {{ etcd_host }}
        etcd_port: 4003
        etcd_peer_port: 2382
        cpulimit: '"100m"'
    - require:
      - service: docker
      - service: kubelet

{% endif %}

{{ pillar.get('systemd_system_path') }}/calico.service:
  file.managed:
    - source: salt://calico/calico.service
    - user: root
    - group: root
    - template: jinja
    - context:
        kubernetes_master_name: {{ pillar['kubernetes_master_name'] }}
        etcd_host: {{ etcd_host }}
        etcd_port: 4003
  cmd.run:
    - name: '/opt/kubernetes/helpers/services bounce calico || true'
    - require:
      - file: /usr/bin/calicoctl
      - file: {{ pillar.get('systemd_system_path') }}/calico.service
