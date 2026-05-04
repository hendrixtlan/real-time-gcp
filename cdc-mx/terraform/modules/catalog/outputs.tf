output "pii_taxonomy_id" {
  value = google_data_catalog_taxonomy.pii.id
}

output "policy_tag_pii_high" {
  value = google_data_catalog_policy_tag.pii_high.id
}

output "policy_tag_pii_medium" {
  value = google_data_catalog_policy_tag.pii_medium.id
}

output "dlp_inspect_template_id" {
  value = google_data_loss_prevention_inspect_template.mx_pii.id
}

output "dlp_deidentify_template_id" {
  value = google_data_loss_prevention_deidentify_template.mx_mask.id
}

output "glossary_id" {
  value = google_dataplex_glossary.main.id
}

output "aspect_type_pii_id" {
  value = google_dataplex_aspect_type.pii_classification.id
}

output "aspect_type_legal_basis_id" {
  value = google_dataplex_aspect_type.legal_basis.id
}

output "aspect_type_purpose_id" {
  value = google_dataplex_aspect_type.purpose.id
}

output "aspect_type_retention_id" {
  value = google_dataplex_aspect_type.retention.id
}
