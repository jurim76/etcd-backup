# etcd-backup

![Version: 0.1.1](https://img.shields.io/badge/Version-0.1.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.1](https://img.shields.io/badge/AppVersion-0.1.1-informational?style=flat-square)

ETCD backup tool

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Juri Malinovski | <coil93@gmail.com> |  |

## Getting Started

#### Create the "etcd-backup" secret

You could use [Vault secret](https://developer.hashicorp.com/vault/docs/platform/k8s/injector/annotations) or [externalsecret](https://external-secrets.io/v0.4.4/api-externalsecret) also.

VAULT_S3 variable contains path to Vault secret file (default path is `/vault/secrets/s3`)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: etcd-backup
type: Opaque
data:
  access_key: <AWS ACCESS_KEY_ID>
  secret_key: <AWS ACCESS_SECRET_KEY>
  bucket: <AWS S3 bucket>
```

#### Create optional `environment-name` configMap
```
apiVersion: v1
kind: ConfigMap
name: environment-name
data:
  env: my-cluster
```

#### Define [schedule](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs) in values.yaml

Default schedule is "@monthly"

```yaml
backup
  schedule: "@yearly"
```

#### Define webhook for slack notification
```yaml
env:
  - name: WEBHOOK_URL
    value: "https://hooks.slack.com/services/<channel-id>"
```

### Install the helm chart

```bash
helm install etcd-backup etcd-backup
```

### TBD Restore the backup

- Enable the pod
```yaml
pod:
  enabled: true
```

- Exec into the pod and run etcd-backup.sh
```bash
# List backups in S3 bucket
/etcd-backup.sh list

# Download the backup from S3 bucket
/etcd-backup.sh download <backup_name>

# Restore the backup (the snapshot restore part should be performed manually)
/etcd-backup.sh load <backup_name>
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| backup.args[0] | string | `"/etcd-backup.sh"` |  |
| backup.args[1] | string | `"backup"` |  |
| backup.schedule | string | `"@monthly"` |  |
| env[0].name | string | `"cacert_file"` |  |
| env[0].value | string | `"/opt/backup/etcd/ca.crt"` |  |
| env[1].name | string | `"cert_file"` |  |
| env[1].value | string | `"/opt/backup/etcd/server.crt"` |  |
| env[2].name | string | `"key_file"` |  |
| env[2].value | string | `"/opt/backup/etcd/server.key"` |  |
| env[3].name | string | `"etcd_endpoints"` |  |
| env[3].value | string | `"https://127.0.0.1:2379"` |  |
| env[4].name | string | `"ACCESS_KEY_ID"` |  |
| env[4].valueFrom.secretKeyRef.key | string | `"access_key"` |  |
| env[4].valueFrom.secretKeyRef.name | string | `"etcd-backup"` |  |
| env[5].name | string | `"ACCESS_SECRET_KEY"` |  |
| env[5].valueFrom.secretKeyRef.key | string | `"secret_key"` |  |
| env[5].valueFrom.secretKeyRef.name | string | `"etcd-backup"` |  |
| env[6].name | string | `"S3_ENDPOINT"` |  |
| env[6].valueFrom.secretKeyRef.key | string | `"endpoint"` |  |
| env[6].valueFrom.secretKeyRef.name | string | `"etcd-backup"` |  |
| env[6].valueFrom.secretKeyRef.optional | bool | `true` |  |
| env[7].name | string | `"S3_BUCKET"` |  |
| env[7].valueFrom.secretKeyRef.key | string | `"bucket"` |  |
| env[7].valueFrom.secretKeyRef.name | string | `"etcd-backup"` |  |
| env[7].valueFrom.secretKeyRef.optional | bool | `true` |  |
| env[8].name | string | `"ENV_NAME"` |  |
| env[8].valueFrom.configMapKeyRef.key | string | `"env"` |  |
| env[8].valueFrom.configMapKeyRef.name | string | `"environment-name"` |  |
| env[8].valueFrom.configMapKeyRef.optional | bool | `true` |  |
| fullnameOverride | string | `""` |  |
| hostNetwork | bool | `true` |  |
| image.pullPolicy | string | `"Always"` |  |
| image.registry | string | `"jurim"` |  |
| image.repository | string | `"etcd-backup"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| initContainer.command | string | `"['sh', '-c', 'chgrp 5001 /opt/backup/etcd/server.key && chmod 0640 /opt/backup/etcd/server.key']"` |  |
| initContainer.name | string | `"busybox"` |  |
| initContainer.repository | string | `"busybox"` |  |
| initContainer.tag | float | `1.37` |  |
| nameOverride | string | `""` |  |
| nodeSelector."node-role.kubernetes.io/control-plane" | string | `""` |  |
| pod.enabled | bool | `true` |  |
| podAnnotations | object | `{}` |  |
| podLabels."app.kubernetes.io/name" | string | `"etcd-backup"` |  |
| podSecurityContext | string | `nil` |  |
| resources.requests.cpu | string | `"100m"` |  |
| resources.requests.memory | string | `"128Mi"` |  |
| securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| securityContext.readOnlyRootFilesystem | bool | `true` |  |
| securityContext.runAsGroup | int | `5001` |  |
| securityContext.runAsNonRoot | bool | `true` |  |
| securityContext.runAsUser | int | `5001` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `"etcd-backup"` |  |
| tolerations[0].effect | string | `"NoSchedule"` |  |
| tolerations[0].key | string | `"node-role.kubernetes.io/control-plane"` |  |
| tolerations[0].operator | string | `"Exists"` |  |
| volumeMounts[0].mountPath | string | `"/opt/backup/data"` |  |
| volumeMounts[0].name | string | `"data"` |  |
| volumeMounts[1].mountPath | string | `"/opt/backup/etcd"` |  |
| volumeMounts[1].name | string | `"etcd-certs"` |  |
| volumes[0].hostPath.path | string | `"/etc/kubernetes/pki/etcd"` |  |
| volumes[0].name | string | `"etcd-certs"` |  |
| volumes[1].emptyDir | object | `{}` |  |
| volumes[1].name | string | `"data"` |  |
