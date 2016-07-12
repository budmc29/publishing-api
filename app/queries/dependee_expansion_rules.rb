module Queries
  module DependeeExpansionRules
    extend DependentExpansionRules
    extend self

  private

    def custom(link_type)
      {
        topical_event: default_fields + [:details],
        placeholder_topical_event: default_fields + [:details],
        organisation: default_fields + [:details],
        placeholder_organisation: default_fields + [:details],
        html_publication: default_fields + [:schema_name, :document_type],
      }[link_type]
    end
  end
end
