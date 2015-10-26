{% set srvc_name = salt['pillar.get']('lookup::zookeeper::service', 'zookeeper') %}
{% set pkg_name = salt['pillar.get']('lookup::zookeeper::pkg', 'zookeeperd') %}
{% set conf_dir = salt['pillar.get']('lookup::zookeeper::conf_dir', '/etc/zookeeper/custom_conf') %}
{% set conf_file = salt['pillar.get']('lookup::zookeeper::conf', '/etc/zookeeper/custom_conf/zoo.cfg') %}
{% set id_file = salt['pillar.get']('lookup::zookeeper::id', '/etc/zookeeper/custom_conf/myid') %}

zookeeper_pkg:
    pkg:
        - installed
        - name: {{ pkg_name }}

zookeeper_service:
    service:
        - running
        - name : {{ srvc_name }}
        - watch:
            - pkg: zookeeper_pkg
            - alternatives: zookeeper_alternative
            - file: zookeeper_main_conf
            - file: zookeeper_id_conf

zookeeper_dir:
    file:
        - recurse
        - name: {{ conf_dir }}
        - source: salt://zookeeper/config

zookeeper_main_conf:
    file.managed:
        - name: {{ conf_file }}
        - source: salt://zookeeper/zoo.cfg
        - template: jinja
        - user: root
        - require:
            - file: zookeeper_dir

zookeeper_id_conf:
    file.managed:
        - name: {{ id_file }}
        - source: salt://zookeeper/myid
        - template: jinja
        - user: root
        - require:
            - file: zookeeper_dir
 
zookeeper_alternative:
    alternatives:
        - install
        - name: zookeeper-conf
        - link: /etc/zookeeper/conf
        - path: {{ conf_dir }}
        - priority: 30
        - require:
            - file: zookeeper_dir

