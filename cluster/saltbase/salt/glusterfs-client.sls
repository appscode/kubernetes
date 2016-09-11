{% if grains['os_family'] == 'RedHat' %}
glusterfs-fuse:
  pkg.installed
{% elif grains.get('os_family', '') == 'Debian'
   and grains.get('oscodename', '') == 'jessie' -%}
glusterfs-pkgrepo:
  pkgrepo.managed:
    - humanname: Glusterfs PPA
    - name: deb http://download.gluster.org/pub/gluster/glusterfs/3.8/3.8.3/Debian/jessie/apt jessie main
    - dist: jessie
    - file: /etc/apt/sources.list.d/gluster.list
    - key_url: http://download.gluster.org/pub/gluster/glusterfs/3.8/3.8.3/rsa.pub
glusterfs-client:
  pkg.latest:
    - refresh: True
    - require:
      - pkgrepo: glusterfs-pkgrepo
# Ubuntu presents as os_family=Debian, osfullname=Ubuntu
{% elif grains.get('os_family', '') == 'Debian'
   and grains.get('oscodename', '') == 'vivid' -%}
glusterfs-client:
  pkg.installed
{% elif grains.get('os_family', '') == 'Debian'
   and grains.get('oscodename', '') == 'wily' -%}
glusterfs-pkgrepo:
  pkgrepo.managed:
    - ppa: gluster/glusterfs-3.7
glusterfs-client:
  pkg.installed:
    - fromrepo: wily
    - require:
      - pkgrepo: glusterfs-pkgrepo
{% endif %}
