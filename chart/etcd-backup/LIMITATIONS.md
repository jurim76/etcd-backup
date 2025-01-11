Limitations:
- etcd-backup uses host network, the internal k8s services are not available in this case
- with host network, only external AWS S3 is available
- etcd-backup requires read access to ETCD private server.key
