require 'test_helper'

class HostIntegrationTest < ActionDispatch::IntegrationTest
  def setup
    Capybara.current_driver = Capybara.javascript_driver
    login_admin
  end

  before do
    SETTINGS[:locations_enabled] = false
    SETTINGS[:organizations_enabled] = false
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.start
    as_admin { @host = FactoryGirl.create(:host, :with_puppet, :managed) }
  end

  after do
    SETTINGS[:locations_enabled] = true
    SETTINGS[:organizations_enabled] = true
    DatabaseCleaner.clean
  end

  def go_to_interfaces_tab
    # go to New Host page
    assert_new_button(hosts_path, "New Host", new_host_path)
    # switch to interfaces tab
    page.find(:link, "Interfaces").click
  end

  def add_interface
    page.find(:button, '+ Add Interface').click

    modal = page.find('#interfaceModal')
    modal.find(:button, "Ok").click
  end

  def modal
    page.find('#interfaceModal')
  end

  def table
    page.find("table#interfaceList")
  end

  def assert_interface_change(change, &block)
    table = page.find("table#interfaceList")
    original_interface_count = table.all('tr', :visible => true).count
    yield
    assert_equal original_interface_count + change, table.all('tr', :visible => true).count
  end

  def index_modal
    page.find('#confirmation-modal')
  end

  def multiple_actions_div
    page.find('#submit_multiple')
  end

  def class_params
    page.find('#inherited_puppetclasses_parameters')
  end

  def select2(value, attrs)
    first("#s2id_#{attrs[:from]}").click
    find(".select2-input").set(value)
    within ".select2-results" do
      find("span", text: value).click
    end
  end

  test "index page" do
    assert_index_page(hosts_path,"Hosts","New Host")
  end

  test "show page" do
    visit hosts_path
    click_link @host.fqdn
    assert page.has_selector?('h1', :text => @host.fqdn), "#{@host.fqdn} <h1> tag, but was not found"
    assert page.has_link?("Properties", :href => "#properties")
    assert page.has_link?("Metrics", :href => "#metrics")
    assert page.has_link?("Templates", :href => "#template")
    assert page.has_link?("Edit", :href => "/hosts/#{@host.fqdn}/edit")
    assert page.has_link?("Build", :href => "/hosts/#{@host.fqdn}#review_before_build")
    assert page.has_link?("Run puppet", :href => "/hosts/#{@host.fqdn}/puppetrun")
    assert page.has_link?("Delete", :href => "/hosts/#{@host.fqdn}")
  end

  describe "create new host page" do
    test "tabs are present" do
      assert_new_button(hosts_path,"New Host",new_host_path)
      assert page.has_link?("Host", :href => "#primary")
      assert page.has_link?("Interfaces", :href => "#network")
      assert page.has_link?("Operating System", :href => "#os")
      assert page.has_link?("Parameters", :href => "#params")
      assert page.has_link?("Additional Information", :href => "#info")
    end

    test "default primary interface is in the overview table" do
      assert_new_button(hosts_path, "New Host", new_host_path)

      # switch to interfaces tab
      page.find(:link, "Interfaces").click

      # test column content
      assert table.find('td.identifier', :visible => true).has_content?('')
      assert table.find('td.type', :visible => true).has_content?('Interface')
      assert table.find('td.mac', :visible => true).has_content?('')
      assert table.find('td.ip', :visible => true).has_content?('')
      assert table.find('td.fqdn', :visible => true).has_content?('')

      # should have table header and the primar interface row
      assert_equal 2, table.all('tr', :visible => true).count

      # test the tlags are set properly
      assert table.find('td.flags .primary-flag.active')
      assert table.find('td.flags .provision-flag.active')
    end

    test 'enables override of hostgroup defaults' do
      env1 = FactoryGirl.create(:environment)
      env2 = FactoryGirl.create(:environment)
      hg1 = FactoryGirl.create(:hostgroup, :environment => env1)
      hg2 = FactoryGirl.create(:hostgroup, :environment => env2)

      visit new_host_path

      select2 hg1.name, :from => 'host_hostgroup_id'

      Timeout.timeout(Capybara.default_wait_time) do
        loop until page.evaluate_script('jQuery.active').zero?
      end

      find("#host_environment_id + .input-group-btn .btn").click

      select2 hg2.name, :from => 'host_hostgroup_id'

      environment = find("#s2id_host_environment_id .select2-chosen").text

      assert_equal env1.name, environment
    end

    describe "NIC modal window" do
      setup { skip "Temporarily disabled until issue #9138 gets resolved" }

      describe "editing interfaces" do
        test "click on edit opens modal" do
          go_to_interfaces_tab

          # edit the primary interface
          table.first(:button, 'Edit').click

          assert modal.find('.modal-content').visible?, "Modal window was shown"
          assert modal.find('.interface_primary').checked?, "Primary checkbox is checked"
          assert modal.find('.interface_provision').checked?, "Provision checkbox is checked"

          modal.find(:button, "Cancel").click

          # test column content
          assert table.find('td.identifier').has_content?('')
          assert table.find('td.type').has_content?('Interface')
          assert table.find('td.mac').has_content?('')
          assert table.find('td.ip').has_content?('')
          assert table.find('td.fqdn').has_content?('')
        end

        test "ok button updates overview table" do
          go_to_interfaces_tab

          # edit the primary interface
          table.first(:button, 'Edit').click

          modal.find('.interface_identifier').set('eth0')
          modal.find('.interface_mac').set('11:22:33:44:55:66')
          modal.find('.interface_ip').set('10.32.8.3')
          modal.find('.interface_name').set('name')

          modal.find(:button, "Ok").click

          assert table.find('td.identifier').has_content?('eth0')
          assert table.find('td.type').has_content?('Interface')
          assert table.find('td.mac').has_content?('11:22:33:44:55:66')
          assert table.find('td.ip').has_content?('10.32.8.3')
          assert table.find('td.fqdn').has_content?('')
        end
      end

      describe "adding interfaces" do
        test "click on add opens modal" do
          go_to_interfaces_tab

          assert_interface_change(0) do
            page.find(:button, '+ Add Interface').click

            assert modal.find('.modal-content').visible?, "Modal window was shown"
            assert !modal.find('.interface_primary').checked?, "Primary checkbox is unchecked by default"
            assert !modal.find('.interface_provision').checked?, "Provision checkbox is unchecked by default"

            modal.find(:button, "Cancel").click
          end
        end

        test "ok button adds new interface" do
          go_to_interfaces_tab

          assert_interface_change(1) do
            page.find(:button, '+ Add Interface').click
            modal.find(:button, "Ok").click
          end
        end

        test "setting primary updates host name" do
          go_to_interfaces_tab

          # edit the primary interface
          table.first(:button, 'Edit').click

          domain = domains(:mydomain)

          modal.find('.interface_name').set('name')
          modal.find('.interface_domain').select(domain.name)

          modal.has_select?('.interface_subnet', :options => domain.subnets.map(&:to_label))
          modal.has_select?('.interface_domain', :selected => domain.name)
          modal.find(:button, "Ok").click

          assert table.find('td.fqdn').has_content?('name.'+domain.name)
          assert page.find('#hostFQDN').has_content?('| name.'+domain.name)

          page.find(:link, "Host").click
          assert_equal 'name', page.find('#host_name').value
        end

        test "selecting domain updates subnet list" do
          disable_orchestration
          go_to_interfaces_tab

          table.first(:button, 'Edit').click

          domain = domains(:mydomain)
          modal.find('.interface_domain').select(domain.name)
          modal.has_select?('.interface_subnet', :options => domain.subnets.map(&:to_label))
          modal.has_select?('.interface_domain', :selected => domain.name)

          # test subnet option list
          subnet_options = modal.find('.interface_subnet').all('option')
          assert_equal subnet_options.map(&:value).sort, domain.subnets.map(&:id).map(&:to_s).sort
          assert_equal subnet_options.map(&:text).sort, domain.subnets.map(&:to_label).sort
        end
      end

      describe "switching flags from the overview table" do
        test "switch primary" do
          go_to_interfaces_tab
          add_interface

          flag_cols = table.all('td.flags')
          flag_cols[1].find('.primary-flag').click

          # only one flag switcher is active
          table.has_css?('.primary-flag.active', :count => 1)

          assert !flag_cols[0].has_css?('.primary-flag.active'), "First interface's flag is inactive"
          assert flag_cols[1].has_css?('.primary-flag.active'), "New interface's flag is active"
        end

        test "switch provisioning" do
          go_to_interfaces_tab
          add_interface

          flag_cols = table.all('td.flags')
          flag_cols[1].find('.provision-flag').click

          # only one flag switcher is active
          table.has_css?('.provision-flag.active', :count => 1)

          assert !flag_cols[0].has_css?('.provision-flag.active'), "First interface's flag is inactive"
          assert flag_cols[1].has_css?('.provision-flag.active'), "New interface's flag is active"
        end
      end

      describe "removing interfaces" do
        test "remove interface" do
          go_to_interfaces_tab
          add_interface

          assert_interface_change(-1) do
            table.all(:button, "Delete").last.click
          end
        end
      end
    end
  end

  test "destroy redirects to hosts index" do
    disable_orchestration  # Avoid DNS errors
    visit hosts_path
    click_link @host.fqdn
    assert page.has_link?("Delete", :href => "/hosts/#{@host.fqdn}")
    first(:link, "Delete").click
    assert_equal(current_path, hosts_path)
  end

  describe "hosts index multiple actions" do
    def test_show_action_buttons
      visit hosts_path
      page.find('#check_all').click

      # Ensure all hosts are checked
      assert page.find('input.host_select_boxes').checked?

      # Dropdown visible?
      assert multiple_actions_div.find('.dropdown-toggle').visible?
      multiple_actions_div.find('.dropdown-toggle').click
      assert multiple_actions_div.find('ul').visible?

      # Hosts are added to cookie
      host_ids_on_cookie = JSON.parse(CGI::unescape(page.driver.cookies['_ForemanSelectedhosts'].value))
      assert(host_ids_on_cookie.include? @host.id)

      # Open modal box
      within('#submit_multiple') do
        click_on('Change Environment')
      end
      assert index_modal.visible?, "Modal window was shown"
      page.find('#environment_id').find("option[value='#{@host.environment_id}']").select_option

      # remove hosts cookie on submit
      index_modal.find('.btn-primary').trigger('click')
      assert_empty(page.driver.cookies['_ForemanSelectedhosts'])
      assert has_selector?("div", :text => "Updated hosts: changed environment")
    end
  end

  describe 'edit page' do
    test 'class parameters and overrides are displayed correctly for booleans' do
      host = FactoryGirl.create(:host, :with_puppetclass)
      FactoryGirl.create(:puppetclass_lookup_key, :as_smart_class_param, :with_override,
                                      :key_type => 'boolean', :default_value => true,
                                      :puppetclass => host.puppetclasses.first, :overrides => {host.lookup_value_matcher => false})
      visit edit_host_path(host)
      assert page.has_link?('Parameters', :href => '#params')
      click_link 'Parameters'
      assert_equal class_params.find("textarea").value, "false"
      refute class_params.find("textarea")[:disabled]
      class_params.find("a[data-tag='remove']").click
      click_button('Submit')
      assert page.has_link?("Edit")

      visit edit_host_path(host)
      assert page.has_link?('Parameters', :href => '#params')
      click_link 'Parameters'
      assert_equal class_params.find("textarea").value, "true"
      assert class_params.find("textarea")[:disabled]
      class_params.find("a[data-tag='override']").click
      refute class_params.find("textarea")[:disabled]
      class_params.find("textarea").set("false")
      click_button('Submit')
      assert page.has_link?("Edit")

      visit edit_host_path(host)
      assert page.has_link?('Parameters', :href => '#params')
      click_link 'Parameters'
      assert_equal class_params.find("textarea").value, "false"
      refute class_params.find("textarea")[:disabled]
    end

    test 'can override puppetclass lookup values' do
      host = FactoryGirl.create(:host, :with_puppetclass)
      FactoryGirl.create(:puppetclass_lookup_key, :as_smart_class_param, :with_override,
                                      :key_type => 'boolean', :default_value => "true",
                                      :puppetclass => host.puppetclasses.first, :overrides => {host.lookup_value_matcher => "false"})

      visit edit_host_path(host)
      assert page.has_link?('Parameters', :href => '#params')
      click_link 'Parameters'
      assert class_params.has_selector?("a[data-tag='remove']", :visible => :visible)
      assert class_params.has_selector?("a[data-tag='override']", :visible => :hidden)
      assert_equal class_params.find("textarea").value, "false"
      refute class_params.find("textarea")[:disabled]

      class_params.find("a[data-tag='remove']").click
      assert class_params.has_selector?("a[data-tag='remove']", :visible => :hidden)
      assert class_params.has_selector?("a[data-tag='override']", :visible => :visible)
      assert_equal class_params.find("textarea").value, "true"
      assert class_params.find("textarea")[:disabled]

      class_params.find("a[data-tag='override']").click
      assert class_params.has_selector?("a[data-tag='remove']", :visible => :visible)
      assert class_params.has_selector?("a[data-tag='override']", :visible => :hidden)
      assert_equal class_params.find("textarea").value, "true"
      refute class_params.find("textarea")[:disabled]
    end

    test 'correctly show hash type overrides' do
      host = FactoryGirl.create(:host, :with_puppetclass)
      FactoryGirl.create(:puppetclass_lookup_key, :as_smart_class_param,
                         :with_override, :key_type => 'hash',
                         :default_value => 'a: b',
                         :puppetclass => host.puppetclasses.first,
                         :overrides => { host.lookup_value_matcher => 'a: c' } )

      visit edit_host_path(host)
      assert page.has_link?('Parameters', :href => '#params')
      click_link 'Parameters'
      assert_equal class_params.find("textarea").value, "a: c\n"
    end

    test 'correctly override global params' do
      host = FactoryGirl.create(:host)

      visit edit_host_path(host)
      assert page.has_link?('Parameters', :href => '#params')
      click_link 'Parameters'
      assert page.has_selector?('#inherited_parameters .btn[data-tag=override]')
      page.find('#inherited_parameters .btn[data-tag=override]').click
      refute page.has_selector?('#inherited_parameters .btn[data-tag=override]')
      click_button('Submit')
      assert page.has_link?("Edit")

      visit edit_host_path(host)
      assert page.has_link?('Parameters', :href => '#params')
      click_link 'Parameters'
      refute page.has_selector?('#inherited_parameters .btn[data-tag=override]')
      page.find('#global_parameters_table a[data-original-title="Remove Parameter"]').click
      assert page.has_selector?('#inherited_parameters .btn[data-tag=override]')
    end

    test 'shows errors on invalid lookup values' do
      host = FactoryGirl.create(:host, :with_puppetclass)
      lookup_key = FactoryGirl.create(:puppetclass_lookup_key, :as_smart_class_param, :with_override,
                                      :key_type => 'boolean', :default_value => true,
                                      :puppetclass => host.puppetclasses.first, :overrides => {host.lookup_value_matcher => false})

      visit edit_host_path(host)
      assert page.has_link?('Parameters', :href => '#params')
      click_link 'Parameters'
      assert page.has_no_selector?('#params td.has-error')

      fill_in "host_lookup_values_attributes_#{lookup_key.id}_value", :with => 'invalid'
      click_button('Submit')
      assert page.has_selector?('#params td.has-error')
    end
  end

  describe 'clone page' do
    test 'clones lookup values' do
      host = FactoryGirl.create(:host, :with_puppetclass)
      lookup_key = FactoryGirl.create(:puppetclass_lookup_key, :as_smart_class_param, :with_override,
                                      :puppetclass => host.puppetclasses.first)
      lookup_value = LookupValue.create(:value => 'abc', :match => host.lookup_value_matcher, :lookup_key_id => lookup_key.id)

      visit clone_host_path(host)
      assert page.has_link?('Parameters', :href => '#params')
      click_link 'Parameters'
      a = page.find("#host_lookup_values_attributes_#{lookup_key.id}_value")
      assert_equal lookup_value.value, a.value
    end

    test 'shows no errors on lookup values' do
      host = FactoryGirl.create(:host, :with_puppetclass)
      FactoryGirl.create(:puppetclass_lookup_key, :as_smart_class_param, :with_override,
                         :puppetclass => host.puppetclasses.first, :overrides => {host.lookup_value_matcher => 'test'})

      visit clone_host_path(host)
      assert page.has_link?('Parameters', :href => '#params')
      click_link 'Parameters'
      assert page.has_no_selector?('#params .has-error')
    end
  end
end
