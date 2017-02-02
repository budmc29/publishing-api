module Presenters
  module Queries
    class ExpandDependents
      def initialize(content_id, controller)
        @content_id = content_id
        @controller = controller
      end

      def expand
        dependents
      end

      def link_graph
        LinkGraph.new(content_id, self)
      end

      def links_by_link_type(content_id)
        links = Link
          .where(target_content_id: content_id)
          .joins(:link_set)
          .where(link_type: rules.reverse_recursive_types)
          .order(link_type: :asc, position: :asc)
          .pluck(:link_type, :content_id)

        grouped = links
          .group_by(&:first)
          .map { |type, values| [type.to_sym, values.map(&:last)] }
        Hash[grouped]
      end

    private

      attr_reader :content_id, :controller

      def dependents
        links = dependent_links
        all_web_content_items = controller.web_content_items(links.map(&:last))

        links.group_by(&:first).each_with_object({}) do |(type, link_array), hash|
          reverse = ::Queries::DependeeExpansionRules.reverse_name_for(type).to_sym
          link_ids = link_array.map(&:last)
          items = all_web_content_items.select { |item| link_ids.include?(item.content_id) }
          expanded = dependent_expanded_items(items)
          if parent
            expanded.map { |e| e[:links] = { type.to_s.to_sym => [expanded_parent] } }
          else
            expanded.map { |e| e[:links] = {} }
          end
          hash[reverse] = expanded
        end
      end

      def expanded_parent
        @expanded_parent ||= parent.to_h.select { |k, _v| rules.expansion_fields(parent.document_type.to_sym).include?(k) }.merge(links: {})
      end

      def parent
        @parent ||= controller.web_content_items([content_id]).first
      end

      def dependent_links
        Link
          .where(target_content_id: content_id)
          .joins(:link_set)
          .where(link_type: rules.reverse_recursive_types)
          .order(link_type: :asc, position: :asc)
          .pluck(:link_type, :content_id)
      end

      def dependent_expanded_items(items)
        items.map do |item|
          expansion_fields = rules.expansion_fields(item.document_type.to_sym)
          item.to_h.select { |k, _v| expansion_fields.include?(k) }
        end
      end

      def rules
        ::Queries::DependentExpansionRules
      end
    end
  end
end
