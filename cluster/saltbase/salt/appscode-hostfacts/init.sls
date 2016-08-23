{{ pillar.get('systemd_system_path') }}/hostfacts.service:
  file.managed:
    - source: salt://appscode-hostfacts/hostfacts.service
    - user: root
    - group: root
  cmd.run:
    - name: '/opt/kubernetes/helpers/services bounce hostfacts || true'
    - require:
      - file: {{ pillar.get('systemd_system_path') }}/hostfacts.service
