/etc/ipsec.conf:
  file.managed:
    - source: salt://appscode-strongswan/ipsec.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - makedirs: true

/etc/ipsec.secrets:
  file.managed:
    - source: salt://appscode-strongswan/ipsec.secrets
    - template: jinja
    - user: root
    - group: root
    - mode: 600
    - makedirs: true
