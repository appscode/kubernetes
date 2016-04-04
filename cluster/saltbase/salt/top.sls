base:
  '*':
    - base
    - debian-auto-upgrades
    - salt-helpers
    - glusterfs-client
{% if grains['cloud'] != 'gce' %}
    - ntp
{% endif %}
{% if pillar.get('e2e_storage_test_environment', '').lower() == 'true' %}
    - e2e
{% endif %}
    - docker-gc

  'roles:kubernetes-pool':
    - match: grain
{% if grains['cloud'] is defined and not grains.cloud in [ 'gce', 'gke' ] %}
    - kube-master-dns
{% endif %}
    - docker
{% if pillar.get('network_provider', '').lower() == 'flannel' %}
    - flannel
{% elif pillar.get('network_provider', '').lower() == 'kubenet' %}
    - cni
{% elif pillar.get('network_provider', '').lower() == 'calico' %}
    - calico
{% endif %}
    - helpers
    - cadvisor
    - kube-client-tools
    - kube-node-unpacker
    - kubelet
{% if pillar.get('network_provider', '').lower() == 'opencontrail' %}
    - opencontrail-networking-minion
{% else %}
    - kube-proxy
{% endif %}
{% if pillar.get('enable_node_logging', '').lower() == 'true' and pillar['logging_destination'] is defined %}
  {% if pillar['logging_destination'] == 'elasticsearch' %}
    - fluentd-es
  {% elif pillar['logging_destination'] == 'gcp' %}
    - fluentd-gcp
  {% endif %}
{% endif %}
{% if pillar.get('enable_cluster_registry', '').lower() == 'true' %}
    - kube-registry-proxy
{% endif %}
    - logrotate

  'roles:kubernetes-master':
    - match: grain
{% if grains['cloud'] is defined and not grains.cloud in [ 'gce', 'gke' ] %}
    - kube-master-dns
{% endif %}
    - etcd
{% if pillar.get('network_provider', '').lower() == 'flannel' %}
    - flannel-server
    - flannel
{% elif pillar.get('network_provider', '').lower() == 'kubenet' %}
    - cni
{% elif pillar.get('network_provider', '').lower() == 'calico' %}
    - calico
{% endif %}
    - kube-apiserver
    - kube-controller-manager
    - kube-scheduler
    - cadvisor
    - kube-client-tools
    - kube-master-addons
    - kube-node-unpacker
    - kube-admission-controls
{% if pillar.get('enable_node_logging', '').lower() == 'true' and pillar['logging_destination'] is defined %}
  {% if pillar['logging_destination'] == 'elasticsearch' %}
    - fluentd-es
  {% elif pillar['logging_destination'] == 'gcp' %}
    - fluentd-gcp
  {% endif %}
{% endif %}
{% if grains['cloud'] is defined and grains['cloud'] != 'vagrant' %}
    - logrotate
{% endif %}
    - kube-addons
{% if grains['cloud'] is defined and grains['cloud'] in [ 'vagrant', 'gce', 'aws', 'vsphere' ] %}
    - docker
    - kubelet
{% endif %}
{% if grains.kubelet_api_servers is defined %}
    - kube-proxy
{% endif %}
{% if pillar.get('network_provider', '').lower() == 'opencontrail' %}
    - opencontrail-networking-master
{% endif %}
