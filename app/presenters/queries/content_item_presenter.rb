# This presenter has been carefully written to run quickly. Please be careful
# if editing its behaviour and make sure to compare benchmarks.
module Presenters
  module Queries
    class ContentItemPresenter
      attr_accessor :scope, :fields, :order, :limit, :offset

      DEFAULT_FIELDS = [
        *ContentItem::TOP_LEVEL_FIELDS,
        :publication_state,
        :user_facing_version,
        :base_path,
        :locale,
        :lock_version,
        :internal_name,
      ]

      def self.present_many(scope, params = {})
        new(scope, params).present_many
      end

      def self.present(content_item)
        translation = Translation.find_by!(content_item: content_item)

        scope = ContentItem.where(content_id: content_item.content_id)
        scope = Translation.filter(scope, locale: translation.locale)

        present_many(scope).first
      end

      def initialize(scope, params = {})
        self.scope = scope
        self.fields = (params[:fields] || DEFAULT_FIELDS).map(&:to_sym)
        self.order = params[:order]
        self.limit = params[:limit]
        self.offset = params[:offset]
      end

      def present_many
        scope = ::Queries::GetLatest.call(self.scope)
        scope = join_supporting_objects(scope)
        scope = order_and_paginate(scope)

        extract_fields(scope)
      end

      def total
        ::Queries::GetLatest.call(self.scope).count
      end

    private

      def join_supporting_objects(scope)
        scope = State.join_content_items(scope)
        scope = UserFacingVersion.join_content_items(scope)
        scope = Translation.join_content_items(scope)
        scope = Location.join_content_items(scope)

        LockVersion.join_content_items(scope)
      end

      def order_and_paginate(scope)
        scope = scope.order(order.to_a.join(" ")) if order
        scope = scope.limit(limit) if limit
        scope = scope.offset(offset) if offset
        scope
      end

      def extract_fields(scope)
        fields_to_select = fields.map do |field|
          case field
          when :publication_state
            "#{publication_state_sql} AS publication_state"
          when :user_facing_version
            "user_facing_versions.number AS user_facing_version"
          when :lock_version
            "lock_versions.number AS lock_version"
          when :description
            "description->>'value' AS description"
          when :internal_name
            "#{internal_name_sql} AS internal_name"
          when :public_updated_at
            "to_char(public_updated_at, '#{iso8601_sql}') as public_updated_at"
          else
            field
          end
        end

        scope = scope.select(*fields_to_select)
        results = evaluate_query(scope)

        parsing_enumerator(results)
      end

      def publication_state_sql
        <<-SQL
          CASE WHEN (user_facing_versions.number > 1 AND states.name = 'draft') THEN
            'redrafted'
          WHEN (states.name = 'published') THEN
            'live'
          ELSE
            states.name
          END
        SQL
      end

      def iso8601_sql
        "YYYY-MM-DD\"T\"HH24:MI:SS\"Z\""
      end

      # This returns the internal_name from the details hash if it is present,
      # otherwise it falls back to the content item's title.
      def internal_name_sql
        "COALESCE(details->>'internal_name', title) "
      end

      def parsing_enumerator(results)
        json_columns = %w(details routes redirects need_ids)
        int_columns = %w(user_facing_version lock_version)

        Enumerator.new do |yielder|
          results.each do |result|
            json_columns.each { |c| parse_json_column(result, c) }
            int_columns.each { |c| parse_int_column(result, c) }

            yielder.yield result
          end
        end
      end

      def parse_json_column(result, column)
        return unless result.key?(column)
        result[column] = JSON.parse(result[column])
      end

      def parse_int_column(result, column)
        return unless result.key?(column)
        result[column] = result[column].to_i
      end

      # It is substantially faster to evaluate directly against Postgres than
      # to use: #as_json, #pluck or even ActiveRecord::Base.connection.execute
      # The reason for this is that the results of this query don't have to go
      # through as many abstraction layers. This is closer to the metal.
      def evaluate_query(scope)
        ActiveRecord::Base.connection.raw_connection.exec(scope.to_sql)
      end
    end
  end
end
