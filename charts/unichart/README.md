# Generic Helm Chart (WIP)

A universal generic chart for many use cases. Supports both stateful and stateless applications.
It can provision deployment, statefulset + headless service for DB, storage with optional NFS and block storage CSIs backend, and ingress.

| Component | Type         | Purpose                                |
|-----------|--------------|----------------------------------------|
| `app`     | Deployment   | The core application logic            |
| `database`      | StatefulSet  | Database                              |
| `Service` | ClusterIP    | Internal service for app access        |
| `Ingress` | Ingress Resource      | External app access (optional)         |
| `Headless Service` | ClusterIP = None | For DB DNS resolution        |
| `persistence` | PV and PVC | Existing or NFS-backend Storage        |

---

## Persistent Storage
Notes about rebinding existing block storage disks for statefulsets. This is a summary of the work completed to support rebinding Proxmox disks on cluster rebuilds.

### App (Deployment)
Static NFS PV, StorageClass is optional. Subdirectories under `persistence.app.nfs.path` are created automatically via `subPath` per app.

### Database (StatefulSet)
Uses `volumeClaimTemplates` with StorageClass (e.g. `proxmox-retain`) (disks are never auto-deleted). Two modes, controlled by `persistence.database.existingVolume.handle`:

#### Fresh install (`handle: ""`)
Dynamic provisioning creates a new empty disk. PVC name is deterministic: `db-storage-<release-name>-0`.

#### Rebind to an existing disk (`handle` set)
Pre-binds the StatefulSet's PVC to a disk that already has data, skipping provisioning entirely. Used after a cluster rebuild, or any time the StatefulSet/PVC needs to be recreated against a disk that already exists.

#### One-time capture (after first install, or any time a new dynamic disk is created)
```shell
kubectl get pv <dynamic-pv-name> -o jsonpath='{.spec.csi.volumeHandle}'
kubectl get pv <dynamic-pv-name> -o jsonpath='{.spec.csi.volumeAttributes}' | jq .
```
Paste both into `persistence.database.existingVolume` in values.yaml and commit.

```yaml
persistence:
  database:
    size: 512Mi
    accessMode: ReadWriteOnce
    storageClassName: proxmox-retain   # must stay identical in both modes
    existingVolume:
      handle: "homelab/pve1/tank/vm-9999-pvc-<uuid>"
      fsType: xfs
      volumeAttributes:
        backup: "0"
        discard: "on"
        iothread: "1"
        replicate: "0"
        ssd: "1"
        storage: tank
```

#### To rebind on a live (already-running) cluster
Setting `handle` alone does nothing to an already-bound PVC. To force a rebind:
```bash
kubectl delete statefulset <name> -n <namespace>
kubectl delete pvc db-storage-<name>-0 -n <namespace>
# disk is untouched, reclaimPolicy: Retain
```
Then update values with the handle and redeploy. The chart creates a static PV with a `claimRef` reserved for `db-storage-<name>-0`, so the new PVC binds to the existing disk instead of provisioning a new one.

#### On a rebuilt cluster
No manual steps needed beyond having the handle already committed. Deploy normally, the static PV pre-binds on first creation.

#### Rules (and learned lessons!)
- `size`, `accessMode`, and `storageClassName` must be identical in both modes. `volumeClaimTemplates` is immutable after creation, changing these on a live StatefulSet will fail.
- Only `existingVolume.handle` and `existingVolume.volumeAttributes` change between fresh install and rebind.
- `existingVolume.volumeAttributes` must be copied verbatim from the live PV, not hand-written.
- Rebind mode only supports `replicaCount: 1` (the `claimRef` targets ordinal `-0` explicitly).
