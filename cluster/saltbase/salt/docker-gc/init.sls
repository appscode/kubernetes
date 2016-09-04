# https://raw.githubusercontent.com/spotify/docker-gc/master/docker-gc
/usr/sbin/docker-gc:
  file.managed:
    - source: salt://docker-gc/docker-gc
    - user: root
    - group: root
    - mode: 744
    - makedirs: true

# Drop the license file into /usr/share so that everything is crystal clear.
/usr/share/doc/docker-gc/LICENSE.txt:
  file.managed:
    - source: salt://docker-gc/LICENSE.txt
    - user: root
    - group: root
    - mode: 644
    - makedirs: true

/etc/cron.hourly/docker-gc:
  file.managed:
    - source: salt://docker-gc/cron
    - user: root
    - group: root
    - mode: 755
