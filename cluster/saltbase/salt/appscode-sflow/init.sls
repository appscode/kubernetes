hsflowd-install:
  pkg.installed:
    - name: hsflowd
    - sources:
      - hsflowd: https://cdn.appscode.com/binaries/sflow/1.29.3/hsflowd_1.29.3-1_amd64.deb

/etc/hsflowd.conf:
  file.managed:
    - source: salt://appscode-sflow/hsflowd.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true
    - dir_mode: 755
    - context:
      ganglia_service_ip: {{ pillar.ganglia_service_ip | default('') }}
    - require:
      - pkg: hsflowd-install

# The service.running block below doesn't work reliably
# Instead we run our script which e.g. does a systemd daemon-reload
# But we keep the service block below, so it can be used by dependencies
# TODO: Fix this
fix-service-hsflowd:
  cmd.wait:
    - name: /opt/kubernetes/helpers/services bounce hsflowd
    - watch:
#     - file: /usr/sbin/hsflowd
      - file: /etc/hsflowd.conf
    - require:
      - pkg: hsflowd-install

hsflowd:
  service.running:
    - enable: True
    - watch:
#     - file: /usr/sbin/hsflowd
      - file: /etc/hsflowd.conf
    - require:
      - pkg: hsflowd-install
