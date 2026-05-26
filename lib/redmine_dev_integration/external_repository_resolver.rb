# frozen_string_literal: true

module RedmineDevIntegration
  class ExternalRepositoryResolver
    class << self
      def github(payload)
        repository = payload['repository'] || {}
        scope = ExternalRepository.where(provider: 'github', active: true)

        repository_id = repository['id'].to_s
        if repository_id.present?
          found = scope.find_by(provider_repository_id: repository_id)
          return found if found
        end

        full_name = repository['full_name'].to_s.presence
        return scope.find_by(full_name: full_name) if full_name

        owner = repository.dig('owner', 'login').to_s.presence
        name = repository['name'].to_s.presence
        return unless owner && name

        scope.find_by(full_name: "#{owner}/#{name}")
      end

      def bitbucket(payload)
        repository = payload['repository'] || {}
        scope = ExternalRepository.where(provider: 'bitbucket', active: true)

        repository_id = repository['uuid'].to_s
        if repository_id.present?
          found = scope.find_by(provider_repository_id: repository_id)
          return found if found
        end

        full_name = repository['full_name'].to_s.presence
        return scope.find_by(full_name: full_name) if full_name

        owner = repository.dig('owner', 'username').to_s.presence
        name = repository['name'].to_s.presence
        return unless owner && name

        scope.find_by(full_name: "#{owner}/#{name}")
      end

      def gitlab(payload)
        repository_id = payload.dig('project', 'id') || payload['project_id'] || payload.dig('repository', 'id')
        return nil if repository_id.blank?
        ExternalRepository.find_by(provider: 'gitlab', provider_repository_id: repository_id.to_s, active: true)
      end
    end
  end
end
