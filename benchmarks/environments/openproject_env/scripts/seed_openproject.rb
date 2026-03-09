# frozen_string_literal: true

# Seed a deterministic OpenProject project and a small set of work packages derived
# from real public data (snapshot downloaded from community.openproject.org).
#
# This script is intended to be executed inside the OpenProject container with a
# Rails runner (production environment).

require 'json'

seed_file = ENV.fetch('OPENPROJECT_SEED_FILE', '/tmp/community_work_packages_snapshot.json')
project_identifier = ENV.fetch('OPENPROJECT_SEED_PROJECT_IDENTIFIER', 'community-snapshot')
project_name = ENV.fetch('OPENPROJECT_SEED_PROJECT_NAME', 'Community Backlog Snapshot')

seed = JSON.parse(File.read(seed_file))
items = seed.fetch('items')

admin = User.find_by(login: 'admin') || User.where(admin: true).order(:id).first
raise 'Admin user not found (expected login=admin)' unless admin

project = Project.find_by(identifier: project_identifier)

unless project
  project = Project.new(
    identifier: project_identifier,
    name: project_name,
    public: true
  )

  # Optional fields vary between versions
  if project.respond_to?(:description=)
    project.description = "Imported snapshot of public work packages from community.openproject.org (downloaded at #{seed['downloaded_at_utc']})."
  end

  if project.respond_to?(:active=)
    project.active = true
  end

  project.save!
end

# Pick a reasonable default type/status/priority. These exist in default seed data.
wp_type = Type.find_by(name: 'Task') || Type.order(:id).first
wp_status = Status.where(is_default: true).order(:id).first || Status.order(:id).first
wp_priority = nil

# OpenProject is historically based on Redmine and commonly uses IssuePriority.
if defined?(IssuePriority)
  wp_priority = IssuePriority.default if IssuePriority.respond_to?(:default)
  wp_priority ||= IssuePriority.where(is_default: true).order(:id).first rescue nil
  wp_priority ||= IssuePriority.order(:id).first rescue nil
end

# Ensure selected type is enabled in the project when applicable.
if wp_type && project.respond_to?(:types) && !project.types.include?(wp_type)
  project.types << wp_type
  project.save!
end

seeded = []

items.each do |item|
  source_id = item['id']
  subject = item['subject'].to_s.strip
  next if subject.empty?

  wp = WorkPackage.where(project_id: project.id, subject: subject).order(:id).first

  unless wp
    wp = WorkPackage.new(
      project: project,
      subject: subject
    )

    if wp.respond_to?(:description=) && item['description_markdown']
      wp.description = item['description_markdown']
    end

    wp.author = admin if wp.respond_to?(:author=)
    wp.type = wp_type if wp.respond_to?(:type=) && wp_type
    wp.status = wp_status if wp.respond_to?(:status=) && wp_status
    wp.priority = wp_priority if wp.respond_to?(:priority=) && wp_priority
    wp.save!
  end

  seeded << {
    'source_id' => source_id,
    'subject' => subject,
    'local_id' => wp.id
  }
end

out = {
  'project_identifier' => project.identifier,
  'project_name' => project.name,
  'seed_file' => seed_file,
  'downloaded_at_utc' => seed['downloaded_at_utc'],
  'work_packages' => seeded
}

puts JSON.pretty_generate(out)
