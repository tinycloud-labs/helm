# storage

Provisions Kubernetes storage on NFS or CSI backends. Create it as its own release so that application releases can `dependsOn` it.

| Mode | Set | Creates |
|---|---|---|
| Static NFS | `persistence.nfs` | PV + PVC |
| Dynamic (NFS or CSI) | `persistence.storageClassName` | PVC |
| Static CSI | `persistence.storageClassName` + `persistence.existingVolume.handle` | PV + PVC |

Conflicting or incomplete combinations fail at render time. See [values.yaml](values.yaml) for all options.

## Static NFS

```yaml
persistence:
  name: media
  size: 100Mi
  accessMode: ReadWriteMany
  nfs:
    server: nfs.example.com
    path: /exports/media
```

## Dynamic

```yaml
persistence:
  name: app-data
  size: 5Gi
  accessMode: ReadWriteOnce
  storageClassName: proxmox-retain
```

If the StorageClass uses `WaitForFirstConsumer`, the PVC stays `Pending` until a pod uses it. Flux must not wait for it, or a release that depends on this one never starts:

```yaml
spec:
  install:
    disableWait: true
  upgrade:
    disableWait: true
```

## Resizing

Raise `persistence.size` if the StorageClass sets `allowVolumeExpansion: true`. Volumes can grow but not shrink, and the filesystem is resized while a pod uses the volume.

## Static CSI (rebinding a disk)

Keeps a disk attached to the same PVC across cluster rebuilds. After the first dynamic install, capture the volume:

```shell
PV=$(kubectl -n <namespace> get pvc <name> -o jsonpath='{.spec.volumeName}')
kubectl get pv "$PV" -o jsonpath='{.spec.csi.volumeHandle}'
kubectl get pv "$PV" -o jsonpath='{.spec.csi.volumeAttributes}'
```

Then add it to the values:

```yaml
persistence:
  name: app-data
  size: 5Gi
  accessMode: ReadWriteOnce
  storageClassName: proxmox-retain
  existingVolume:
    handle: "homelab/pve1/tank/vm-9999-pvc-example"
    fsType: xfs
    volumeAttributes:
      ssd: "1"
      storage: tank
```

- `name`, `storageClassName` and `size` must match the existing PVC.
- On a running cluster the PVC stays on its current PV, and the new PV sits unused until the next rebuild.
- The PV is always `Retain` and is kept on uninstall. To reuse it on the same cluster after an uninstall, clear `spec.claimRef.uid`.
- Once the PV is bound, its capacity is read from the cluster rather than `size`, so resizing works as for dynamic volumes.
- Proxmox `nodeAffinity` comes from the handle. For other drivers, set `existingVolume.driver` and, if needed, `existingVolume.nodeAffinity`.
