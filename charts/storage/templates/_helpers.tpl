{{/* Name of the PVC, and of the PV when the chart creates one. */}}
{{- define "storage.name" -}}
{{- .Values.persistence.name | default .Release.Name -}}
{{- end -}}

{{/* Namespace of the PVC. */}}
{{- define "storage.namespace" -}}
{{- .Values.namespace | default .Release.Namespace -}}
{{- end -}}

{{/* Common labels, merged with .Values.labels. */}}
{{- define "storage.labels" -}}
{{- $defaults := dict "app.kubernetes.io/name" .Chart.Name "app.kubernetes.io/instance" .Release.Name "app.kubernetes.io/managed-by" .Release.Service -}}
{{- toYaml (merge (dict) .Values.labels $defaults) -}}
{{- end -}}

{{/*
Validates persistence and returns the storage mode:
  nfs-static  PV and PVC for an NFS share
  csi-static  PV and PVC for an existing CSI volume
  dynamic     PVC only, provisioned by a StorageClass
*/}}
{{- define "storage.mode" -}}
{{- $p := .Values.persistence -}}
{{- $handle := $p.existingVolume.handle -}}
{{- if or $p.nfs.server $p.nfs.path -}}
  {{- if or $p.storageClassName $handle -}}
    {{- fail "persistence.nfs cannot be combined with persistence.storageClassName or persistence.existingVolume" -}}
  {{- end -}}
  {{- if not (and $p.nfs.server $p.nfs.path) -}}
    {{- fail "persistence.nfs requires both server and path" -}}
  {{- end -}}
  nfs-static
{{- else if not $p.storageClassName -}}
  {{- fail "set persistence.nfs, or persistence.storageClassName for CSI and dynamic storage" -}}
{{- else if $handle -}}
  csi-static
{{- else -}}
  dynamic
{{- end -}}
{{- end -}}

{{/* nodeAffinity of an existing CSI volume, explicit or derived from a Proxmox handle. */}}
{{- define "storage.nodeAffinity" -}}
{{- $ev := .Values.persistence.existingVolume -}}
{{- if $ev.nodeAffinity -}}
{{- toYaml $ev.nodeAffinity -}}
{{- else if eq $ev.driver "csi.proxmox.sinextra.dev" -}}
{{- $parts := splitList "/" $ev.handle -}}
{{- if ne (len $parts) 4 -}}
  {{- fail "persistence.existingVolume.handle must be <region>/<zone>/<storage>/<disk> for Proxmox" -}}
{{- end -}}
required:
  nodeSelectorTerms:
    - matchExpressions:
        - key: topology.kubernetes.io/region
          operator: In
          values:
            - {{ index $parts 0 | quote }}
        - key: topology.kubernetes.io/zone
          operator: In
          values:
            - {{ index $parts 1 | quote }}
{{- end -}}
{{- end -}}
