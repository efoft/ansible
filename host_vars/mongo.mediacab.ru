network:
  intif:
    device:  ens160
    uuid:    f03552ed-ed56-4fd3-90e3-35d3da43125e
    ip:      192.168.1.103
    prefix:  24
    gateway: 192.168.1.1
    dns:
      - 192.168.1.1
    zone:    internal
netcfg: "nm"

vgname: "md0vg"
mongodb:
  listen:  intip
  lvsize:  70G
  auth:    enabled
  replSet: rs01

bacula:
  client:
    director_name: "imm.mediacab.ru"
    server: 192.168.1.1

nagios:
  client:
    server: 192.168.1.1
