# /usr/bin/env ruby

require ::File.expand_path('../../config/environment', __FILE__)
require 'benchmark'
require 'securerandom'

require 'faker'
require 'stackprof'

abort "Refusing to run outside of development" unless Rails.env.development?

$queries = 0
ActiveSupport::Notifications.subscribe "sql.active_record" do |name, started, finished, unique_id, data|
  $queries += 1
end

content_id = SecureRandom.uuid
title = Faker::Company.catch_phrase

content_items = 100.times.map do
  {
    content_id: content_id,
    format: "placeholder",
    schema_name: "placeholder",
    document_type: "placeholder",
    title: title,
    base_path: "/performance-testing/#{title.parameterize}",
    description: Faker::Lorem.paragraph,
    public_updated_at: Time.now.iso8601,
    locale: "en",
    routes: [
      {path: "/performance-testing/#{title.parameterize}", type: "exact"}
    ],
    redirects: [],
    publishing_app: "performance-testing",
    rendering_app: "performance-testing",
    details: {
      body: "<p>#{Faker::Lorem.paragraphs(10)}</p>"
    },
    phase: 'live',
    need_ids: []
  }
end

begin
  StackProf.run(mode: :wall, out: "tmp/put_content_wall.dump") do
    puts Benchmark.measure {
      content_items.each do |item|
        Commands::V2::PutContent.call(item)
        print "."
      end
      puts ""
    }
  end

  puts "#{$queries} SQL queries"

ensure
  scope = ContentItem.where(publishing_app: 'performance-testing')
  LinkSet.includes(:links).where(content_id: scope.pluck(:content_id)).destroy_all
  Location.where(content_item: scope).delete_all
  State.where(content_item: scope).delete_all
  Translation.where(content_item: scope).delete_all
  UserFacingVersion.where(content_item: scope).delete_all
  LockVersion.where(target: scope).delete_all
  scope.delete_all
end