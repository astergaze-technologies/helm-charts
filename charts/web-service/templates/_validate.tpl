{{- define "web-service.validate" -}}
{{- if and .Values.httpRoute.enabled (not .Values.httpRoute.hostnames) }}
  {{- fail "httpRoute.enabled is true but hostnames is empty. An HTTPRoute with no hostnames matches every host on the shared Gateway and would take other tenants' traffic." }}
{{- end }}
{{- if and .Values.httpRoute.enabled (not .Values.service.enabled) }}
  {{- fail "httpRoute.enabled needs service.enabled - a route with no Service resolves to BackendNotFound." }}
{{- end }}
{{- if and .Values.autoscaling.enabled (not .Values.resources.requests) }}
  {{- fail "autoscaling.enabled needs resources.requests - an HPA on CPU or memory has nothing to compute a percentage against." }}
{{- end }}
{{- end }}
