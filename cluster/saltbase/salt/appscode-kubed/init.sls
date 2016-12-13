# kubed in a static pod
/etc/kubernetes/manifests/appscode-kubed.manifest:
  file.managed:
    - source: salt://appscode-kubed/appscode-kubed.manifest
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true
    - dir_mode: 755
    - context:
      appscode_api_grpc_endpoint: {{ pillar['appscode_api_grpc_endpoint'] }}
      cloud_provider: {{ grains.get('cloud', '') }}
      cluster_name: {{ pillar['instance_prefix'] }}
    - require:
      - service: docker
      - service: kubelet
