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
    - appscode-hostfacts

  'roles:kubernetes-pool':
    - match: grain
{% if grains['cloud'] is defined and not grains.cloud in [ 'gce', 'gke' ] %}
    - kube-master-dns
{% endif %}
    - docker
{% if pillar.get('enable_cluster_vpn', '').lower() == 'h2h-psk' %}
    - strongswan-h2h-psk
{% endif %}
{% if pillar.get('network_provider', '').lower() == 'flannel' %}
    - flannel
{% endif %}
{% if pillar.get('network_policy_provider', '').lower() == 'calico' %}
    - cni
{% elif pillar.get('network_provider', '').lower() == 'kubenet' %}
    - cni
{% elif pillar.get('network_provider', '').lower() == 'cni' %}
    - cni
{% endif %}
{% if grains['cloud'] is defined and grains['cloud'] == 'azure-legacy' %}
    - openvpn-client
{% endif %}
    - helpers
    - kube-client-tools
    - kube-node-unpacker
    - kubelet
{% if pillar.get('network_provider', '').lower() == 'opencontrail' %}
    - opencontrail-networking-minion
{% else %}
    - kube-proxy
{% endif %}
{% if pillar.get('enable_node_logging', '').lower() == 'true' and pillar['logging_destination'] is defined %}
  {% if pillar['logging_destination'] in ['elasticsearch', 'appscode-elasticsearch'] %}
    - fluentd-es
  {% elif pillar['logging_destination'] == 'gcp' %}
    - fluentd-gcp
  {% endif %}
{% endif %}
{% if pillar.get('enable_cluster_registry', '').lower() == 'true' %}
    - kube-registry-proxy
{% endif %}
{% if pillar['prepull_e2e_images'] is defined and pillar['prepull_e2e_images'].lower() == 'true' %}
    - e2e-image-puller
{% endif %}
    - logrotate
{% if pillar.get('network_policy_provider', '').lower() == 'calico' %}
    - calico.node
{% endif %}

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
{% elif pillar.get('network_provider', '').lower() == 'cni' %}
    - cni
{% endif %}
{% if pillar.get('enable_l7_loadbalancing', '').lower() == 'glbc' %}
    - l7-gcp
{% endif %}
    - kube-apiserver
    - kube-controller-manager
    - kube-scheduler
    - kube-client-tools
    - kube-master-addons
    - kube-node-unpacker
    - kube-admission-controls
{% if pillar.get('enable_node_logging', '').lower() == 'true' and pillar['logging_destination'] is defined %}
  {% if pillar['logging_destination'] in ['elasticsearch', 'appscode-elasticsearch'] %}
    - fluentd-es
  {% elif pillar['logging_destination'] == 'gcp' %}
    - fluentd-gcp
  {% endif %}
{% endif %}
{% if grains['cloud'] is defined and grains['cloud'] != 'vagrant' %}
    - logrotate
{% endif %}
    - kube-addons
{% if grains['cloud'] is defined and grains['cloud'] == 'azure-legacy' %}
    - openvpn
    - nginx
{% endif %}
{% if grains['cloud'] is defined and grains['cloud'] in [ 'vagrant', 'gce', 'aws', 'vsphere', 'photon-controller', 'openstack', 'azure-legacy'] %}
    - docker
    - kubelet
{% endif %}
{% if pillar.get('enable_cluster_vpn', '').lower() == 'h2h-psk' %}
    - strongswan-h2h-psk
{% endif %}
{% if grains.kubelet_api_servers is defined %}
    - kube-proxy
{% endif %}
    - appscode-kubed
{% if pillar.get('network_provider', '').lower() == 'opencontrail' %}
    - opencontrail-networking-master
{% endif %}
{% if pillar.get('enable_cluster_autoscaler', '').lower() == 'true' %}
    - cluster-autoscaler
{% endif %}
{% if pillar.get('enable_rescheduler', '').lower() == 'true' %}
    - rescheduler
{% endif %}
{% if pillar.get('network_policy_provider', '').lower() == 'calico' %}
    - calico.master
{% endif %}
