output "id" {
  value = google_memorystore_instance.this.id
}

output "instance_id" {
  value = google_memorystore_instance.this.instance_id
}

output "state" {
  value = google_memorystore_instance.this.state
}

output "name" {
  value = google_memorystore_instance.this.name
}

output "psc_attachment_details" {
  value = [
    for a in google_memorystore_instance.this.psc_attachment_details : {
      connection_type    = a.connection_type
      service_attachment = a.service_attachment
    }
  ]
}

output "discovery_endpoints" {
  value = flatten([
    for e in google_memorystore_instance.this.endpoints : [
      for c in e.connections : {
        ip_address         = c.psc_auto_connection[0].ip_address
        port               = c.psc_auto_connection[0].port
        network            = c.psc_auto_connection[0].network
        service_attachment = c.psc_auto_connection[0].service_attachment
        forwarding_rule    = c.psc_auto_connection[0].forwarding_rule
      }
      if c.psc_auto_connection[0].connection_type == "CONNECTION_TYPE_DISCOVERY"
    ]
  ])
}
