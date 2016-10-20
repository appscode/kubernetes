/etc/kube-flannel/cni-conf.json:
  file.managed:
    - source: salt://kube-flannel/cni-conf.json
    - template: jinja
    - user: root
    - group: root
    - mode: 400
    - makedirs: true

/etc/kube-flannel/net-conf.json:
  file.managed:
    - source: salt://kube-flannel/net-conf.json
    - template: jinja
    - user: root
    - group: root
    - mode: 400
    - makedirs: true

/var/lib/kube-flannel/kubeconfig:
  file.managed:
    - source: salt://kubelet/kubeconfig
    - user: root
    - group: root
    - mode: 400
    - makedirs: true

# kube-flannel in a static pod
/etc/kubernetes/manifests/kube-flannel.manifest:
  file.managed:
    - source: salt://kube-flannel/kube-flannel.manifest
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true
    - dir_mode: 755
    - require:
      - service: docker
      - service: kubelet

/var/log/kube-flannel.log:
  file.managed:
    - user: root
    - group: root
    - mode: 644
