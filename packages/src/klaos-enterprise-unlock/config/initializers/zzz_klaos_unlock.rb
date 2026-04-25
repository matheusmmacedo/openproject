# frozen_string_literal: true
# KLaOS local unlock — self-hosted GPLv3 modification.
# Loaded last (zzz_ prefix) so it overrides any upstream behavior.

Rails.application.config.after_initialize do
  begin
    next unless defined?(EnterpriseToken)

    Rails.logger.info "[klaos-unlock] applying EnterpriseToken bypass"

    klaos_unlock = Module.new do
      def active?(*); true; end
      def trial_only?(*); false; end
      def trialling?(*); false; end
      def trialling_features(*); Set.new; end
      def hide_banners?(*); true; end
      def show_banners?(*); false; end
      def will_expire?(*); false; end
      def allows_to?(*); true; end
      def user_limit(*); nil; end
      def days_until_expiration(*); 36_500; end
      def available_features(*)
        if defined?(OpenProject::Token::FEATURES)
          OpenProject::Token::FEATURES.to_set
        else
          # Fallback: flat list of known EE features. Authorization::EnterpriseService
          # paths still get the truthy `allows_to?` above, so this list is mostly cosmetic.
          %i[
            attribute_help_texts
            board_view conditional_highlighting custom_actions custom_field_hierarchies
            custom_field_in_wp custom_fields_in_projects_list custom_styles
            date_alerts define_custom_style document_categories edit_attribute_groups
            grid_widget_news ldap_groups ldap_user_authentication
            multiple_custom_fields_for_users notification_for_news
            ocr_with_tesseract one_drive_sharepoint_file_storage openid_providers
            openid_providers_microsoft openid_providers_okta_keycloak
            otp_via_email otp_via_sms password_check_via_haveibeenpwned
            placeholder_users powerbi_dashboard project_filters project_list_sharing
            project_status_dashboard remoting role_grouping search_user_settings
            sharing_user_groups storage_groups team_planner_view two_factor_authentication
            wiki_export work_package_query_relation_columns work_package_sharing
            workflow_overview wp_pdf_export
          ].to_set
        end
      end
    end

    EnterpriseToken.singleton_class.prepend(klaos_unlock)

    if defined?(OpenProject::Configuration) && OpenProject::Configuration.respond_to?(:ee_hide_banners?)
      OpenProject::Configuration.singleton_class.prepend(Module.new do
        def ee_hide_banners?(*); true; end
      end)
    end
  rescue => e
    Rails.logger.error "[klaos-unlock] failed: #{e.class}: #{e.message}"
  end
end
