{{- define "malus.selector" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/part-of: malus
{{- end }}

{{- define "malus.labels" -}}
{{ include "malus.selector" . }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
{{- end }}

{{- define "malus.config" -}}
{{- toYaml (mergeOverwrite (deepCopy .root.Values.defaults) (deepCopy .svc)) }}
{{- end }}

{{- define "malus.image" -}}
{{ .root.Values.global.image.repository }}{{ .root.Values.global.image.separator }}{{ .name }}:{{ .root.Values.global.image.tag }}
{{- end }}

{{- define "malus.podLabels" -}}
{{ include "malus.selector" . }}
{{- if .root.Values.global.workloadIdentity }}
azure.workload.identity/use: "true"
{{- end }}
{{- end }}

{{- define "malus.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 65532
runAsGroup: 65532
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{- define "malus.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end }}

{{- define "malus.env" -}}
- name: APP_ENV
  value: {{ .root.Values.global.appEnv | quote }}
- name: LOG_LEVEL
  value: {{ .root.Values.global.logLevel | quote }}
- name: PORT
  value: {{ .cfg.port | int | quote }}
- name: OTEL_SERVICE_NAME
  value: {{ .name | quote }}
{{- range $k, $v := mergeOverwrite (deepCopy (.root.Values.global.env | default dict)) (deepCopy (.cfg.env | default dict)) }}
- name: {{ $k }}
  value: {{ $v | quote }}
{{- end }}
{{- end }}

{{- define "malus.envFrom" -}}
{{- if .cfg.secretEnv }}
envFrom:
  - secretRef:
      name: {{ .name }}-env
{{- end }}
{{- end }}
