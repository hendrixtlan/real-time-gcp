# =============================================================================
# Module: catalog
# Knowledge Catalog + DLP + Policy Tags para LFPDPPP.
# Aspect types: pii-classification, legal-basis, purpose, retention.
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
  }
}

# -----------------------------------------------------------------------------
# Aspect types
# -----------------------------------------------------------------------------
resource "google_dataplex_aspect_type" "pii_classification" {
  project        = var.project_id
  location       = "global"
  aspect_type_id = "lfpdppp-pii-classification"
  display_name   = "LFPDPPP - PII classification"
  description    = "Clasificación de datos personales según LFPDPPP"

  metadata_template = jsonencode({
    name = "lfpdppp-pii-classification"
    type = "record"
    recordFields = [
      {
        name = "sensitivity_level"
        type = {
          name = "enum", type = "enum"
          enumValues = [
            { name = "PUBLIC" }, { name = "INTERNAL" },
            { name = "CONFIDENTIAL" }, { name = "RESTRICTED" }
          ]
        }
      },
      {
        name = "pii_category"
        type = {
          name = "enum", type = "enum"
          enumValues = [
            { name = "NONE" }, { name = "NAME" }, { name = "EMAIL" },
            { name = "PHONE" }, { name = "ADDRESS" },
            { name = "CURP" }, { name = "RFC" }, { name = "NSS" },
            { name = "INE_IFE" }, { name = "CLABE" },
            { name = "CARD_PAN" }, { name = "BIOMETRIC" },
            { name = "FINANCIAL" }, { name = "HEALTH" },
            { name = "POLITICAL" }, { name = "RELIGIOUS" },
            { name = "ETHNIC" }, { name = "SEXUAL_PREFERENCE" }
          ]
        }
      },
      { name = "is_sensitive_lfpdppp", type = { name = "boolean", type = "boolean" } },
      { name = "data_steward", type = { name = "string", type = "string" } }
    ]
  })
}

resource "google_dataplex_aspect_type" "legal_basis" {
  project        = var.project_id
  location       = "global"
  aspect_type_id = "lfpdppp-legal-basis"
  display_name   = "LFPDPPP - Legal basis"
  description    = "Base legal del tratamiento (Art. 8)"

  metadata_template = jsonencode({
    name = "lfpdppp-legal-basis"
    type = "record"
    recordFields = [
      {
        name = "basis_type"
        type = {
          name = "enum", type = "enum"
          enumValues = [
            { name = "CONSENT_EXPRESS" }, { name = "CONSENT_TACIT" },
            { name = "LEGAL_OBLIGATION" }, { name = "CONTRACT_EXECUTION" },
            { name = "VITAL_INTEREST" }, { name = "PUBLIC_INTEREST" },
            { name = "JUDICIAL_ORDER" }
          ]
        }
      },
      { name = "legal_reference", type = { name = "string", type = "string" } },
      { name = "withdrawal_mechanism_url", type = { name = "string", type = "string" } }
    ]
  })
}

resource "google_dataplex_aspect_type" "purpose" {
  project        = var.project_id
  location       = "global"
  aspect_type_id = "lfpdppp-purpose"
  display_name   = "LFPDPPP - Purpose"
  description    = "Finalidad del tratamiento (Art. 16)"

  metadata_template = jsonencode({
    name = "lfpdppp-purpose"
    type = "record"
    recordFields = [
      { name = "primary_purpose", type = { name = "string", type = "string" } },
      {
        name = "category"
        type = {
          name = "enum", type = "enum"
          enumValues = [
            { name = "NECESSARY" }, { name = "SECONDARY" },
            { name = "ANALYTICS" }, { name = "MARKETING" },
            { name = "FRAUD_PREVENTION" }, { name = "REGULATORY_REPORTING" }
          ]
        }
      },
      { name = "privacy_notice_url", type = { name = "string", type = "string" } },
      { name = "privacy_notice_version", type = { name = "string", type = "string" } }
    ]
  })
}

resource "google_dataplex_aspect_type" "retention" {
  project        = var.project_id
  location       = "global"
  aspect_type_id = "lfpdppp-retention"
  display_name   = "LFPDPPP - Retention policy"
  description    = "Política de retención (Art. 11)"

  metadata_template = jsonencode({
    name = "lfpdppp-retention"
    type = "record"
    recordFields = [
      { name = "retention_days", type = { name = "integer", type = "long" } },
      {
        name = "retention_basis"
        type = {
          name = "enum", type = "enum"
          enumValues = [
            { name = "BUSINESS_NEED" }, { name = "LEGAL_OBLIGATION" },
            { name = "STATUTE_OF_LIMITATIONS" }, { name = "CONTRACTUAL" }
          ]
        }
      },
      { name = "deletion_method", type = { name = "string", type = "string" } }
    ]
  })
}

# -----------------------------------------------------------------------------
# Glosario de negocio
# -----------------------------------------------------------------------------
resource "google_dataplex_glossary" "main" {
  project      = var.project_id
  location     = var.region
  glossary_id  = "${var.prefix}-glossary"
  display_name = "Glosario CDC + LFPDPPP"
  description  = "Términos compartidos del stack CDC con cumplimiento LFPDPPP"
}

# -----------------------------------------------------------------------------
# Policy tags para column-level security en BigQuery
# -----------------------------------------------------------------------------
resource "google_data_catalog_taxonomy" "pii" {
  project                = var.project_id
  region                 = var.region
  display_name           = "${var.prefix}-pii-taxonomy"
  description            = "Taxonomía PII para column-level access control"
  activated_policy_types = ["FINE_GRAINED_ACCESS_CONTROL"]
}

resource "google_data_catalog_policy_tag" "pii_high" {
  taxonomy     = google_data_catalog_taxonomy.pii.id
  display_name = "pii-high"
  description  = "PII alta sensibilidad (LFPDPPP datos sensibles)"
}

resource "google_data_catalog_policy_tag" "pii_medium" {
  taxonomy     = google_data_catalog_taxonomy.pii.id
  display_name = "pii-medium"
  description  = "PII media (email, phone, name)"
}

# -----------------------------------------------------------------------------
# DLP — Stored InfoTypes mexicanos
# -----------------------------------------------------------------------------
resource "google_data_loss_prevention_stored_info_type" "curp" {
  parent       = "projects/${var.project_id}/locations/${var.region}"
  description  = "Clave Única de Registro de Población"
  display_name = "MX_CURP"
  regex {
    pattern = "[A-Z][AEIOUX][A-Z]{2}[0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])[HM](AS|BC|BS|CC|CS|CH|CL|CM|DF|DG|GT|GR|HG|JC|MC|MN|MS|NT|NL|OC|PL|QT|QR|SP|SL|SR|TC|TS|TL|VZ|YN|ZS|NE)[B-DF-HJ-NP-TV-Z]{3}[0-9A-Z][0-9]"
  }
}

resource "google_data_loss_prevention_stored_info_type" "rfc_fisica" {
  parent       = "projects/${var.project_id}/locations/${var.region}"
  description  = "RFC persona física (13 chars)"
  display_name = "MX_RFC_FISICA"
  regex {
    pattern = "[A-ZÑ&]{4}[0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])[A-Z0-9]{2}[0-9A]"
  }
}

resource "google_data_loss_prevention_stored_info_type" "rfc_moral" {
  parent       = "projects/${var.project_id}/locations/${var.region}"
  description  = "RFC persona moral (12 chars)"
  display_name = "MX_RFC_MORAL"
  regex {
    pattern = "[A-ZÑ&]{3}[0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])[A-Z0-9]{2}[0-9A]"
  }
}

resource "google_data_loss_prevention_stored_info_type" "nss" {
  parent       = "projects/${var.project_id}/locations/${var.region}"
  description  = "Número de Seguridad Social IMSS"
  display_name = "MX_NSS"
  regex {
    pattern = "[0-9]{2}[0-9]{2}[0-9]{6}[0-9]"
  }
}

resource "google_data_loss_prevention_stored_info_type" "clave_elector" {
  parent       = "projects/${var.project_id}/locations/${var.region}"
  description  = "Clave de Elector INE/IFE"
  display_name = "MX_CLAVE_ELECTOR"
  regex {
    pattern = "[A-Z]{6}[0-9]{8}[HM][0-9]{3}"
  }
}

resource "google_data_loss_prevention_stored_info_type" "clabe" {
  parent       = "projects/${var.project_id}/locations/${var.region}"
  description  = "CLABE interbancaria"
  display_name = "MX_CLABE"
  regex {
    pattern = "[0-9]{18}"
  }
}

# -----------------------------------------------------------------------------
# DLP inspect template (PII MX + estándar)
# -----------------------------------------------------------------------------
resource "google_data_loss_prevention_inspect_template" "mx_pii" {
  parent       = "projects/${var.project_id}/locations/${var.region}"
  description  = "Detección PII mexicano + estándar para LFPDPPP"
  display_name = "${var.prefix}-mx-pii-inspect"

  inspect_config {
    info_types { name = "EMAIL_ADDRESS" }
    info_types { name = "PHONE_NUMBER" }
    info_types { name = "CREDIT_CARD_NUMBER" }
    info_types { name = "PERSON_NAME" }
    info_types { name = "DATE_OF_BIRTH" }
    info_types { name = "IBAN_CODE" }
    info_types { name = "IP_ADDRESS" }
    info_types { name = "MEXICO_CURP_NUMBER" }

    custom_info_types {
      info_type { name = "MX_CURP_CUSTOM" }
      stored_type { name = google_data_loss_prevention_stored_info_type.curp.id }
      likelihood = "VERY_LIKELY"
    }
    custom_info_types {
      info_type { name = "MX_RFC_FISICA" }
      stored_type { name = google_data_loss_prevention_stored_info_type.rfc_fisica.id }
      likelihood = "LIKELY"
    }
    custom_info_types {
      info_type { name = "MX_NSS" }
      stored_type { name = google_data_loss_prevention_stored_info_type.nss.id }
      likelihood = "POSSIBLE"
    }
    custom_info_types {
      info_type { name = "MX_CLAVE_ELECTOR" }
      stored_type { name = google_data_loss_prevention_stored_info_type.clave_elector.id }
      likelihood = "VERY_LIKELY"
    }
    custom_info_types {
      info_type { name = "MX_CLABE" }
      stored_type { name = google_data_loss_prevention_stored_info_type.clabe.id }
      likelihood = "LIKELY"
    }

    min_likelihood = "POSSIBLE"
    limits {
      max_findings_per_request = 1000
    }
    include_quote = false
  }
}

# -----------------------------------------------------------------------------
# DLP deidentify template (para exports y respuestas ARCO)
# -----------------------------------------------------------------------------
resource "google_data_loss_prevention_deidentify_template" "mx_mask" {
  parent       = "projects/${var.project_id}/locations/${var.region}"
  description  = "Enmascarado de PII para exports"
  display_name = "${var.prefix}-mx-pii-deidentify"

  deidentify_config {
    info_type_transformations {
      transformations {
        info_types { name = "MX_CURP_CUSTOM" }
        info_types { name = "MX_RFC_FISICA" }
        info_types { name = "MX_NSS" }
        info_types { name = "EMAIL_ADDRESS" }
        info_types { name = "PHONE_NUMBER" }
        info_types { name = "CREDIT_CARD_NUMBER" }

        primitive_transformation {
          character_mask_config {
            masking_character = "*"
            number_to_mask    = -1
            reverse_order     = false
          }
        }
      }
    }
  }
}
