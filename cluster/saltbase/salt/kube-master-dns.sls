resolve-kube-master:
  host.present:
    - ip: {{ pillar['master_internal_ip'] }}
    - names:
      - {{ pillar['kubernetes_master_name'] }}
