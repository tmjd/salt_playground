zookeeper:
    pkg.installed
        - name: {{ pillar['lookup']['zookeeper']['pkg'] }}

zookeeper_service:
    service.running:
        - name : {{ pillar['lookup']['zookeeper']['service'] }}
        - require:
            - pkg: zookeeper

