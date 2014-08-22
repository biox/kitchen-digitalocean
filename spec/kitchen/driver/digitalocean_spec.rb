# -*- encoding: utf-8 -*-
#
# Author:: Jonathan Hartman (<j@p4nt5.com>)
#
# Copyright (C) 2013, Jonathan Hartman
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative '../../spec_helper'

require 'logger'
require 'stringio'
require 'rspec'
require 'kitchen'

describe Kitchen::Driver::Digitalocean do
  let(:logged_output) { StringIO.new }
  let(:logger) { Logger.new(logged_output) }
  let(:config) { Hash.new }
  let(:state) { Hash.new }
  let(:platform_name) { 'ubuntu' }

  let(:instance) do
    double(
      name: 'potatoes',
      logger: logger,
      to_str: 'instance',
      platform: double(name: platform_name)
    )
  end

  let(:driver) do
    d = Kitchen::Driver::Digitalocean.new(config)
    d.instance = instance
    d
  end

  before(:each) do
    ENV['DIGITALOCEAN_ACCESS_TOKEN'] = 'access_token'
    ENV['DIGITALOCEAN_SSH_KEY_IDS'] = '1234'
  end

  describe '#initialize'do
    context 'default options' do
      it 'defaults to the smallest flavor size' do
        expect(driver[:size]).to eq('512mb')
      end

      it 'defaults to SSH with root user on port 22' do
        expect(driver[:username]).to eq('root')
        expect(driver[:port]).to eq('22')
      end

      it 'defaults to a random server name' do
        expect(driver[:server_name]).to be_a(String)
      end

      it 'defaults to region id 1' do
        expect(driver[:region]).to eq('nyc2')
      end

      it 'defaults to SSH Key Ids from $SSH_KEY_IDS' do
        expect(driver[:ssh_key_ids]).to eq('1234')
      end

      it 'defaults to Access Token from $DIGITALOCEAN_ACCESS_TOKEN' do
        expect(driver[:digitalocean_access_token]).to eq('access_token')
      end
    end

    context 'name is ubuntu-14-04-x64' do
      let(:platform_name) { 'ubuntu-14-04-x64' }

      it 'defaults to the correct image ID' do
        expect(driver[:image]).to eq('ubuntu-14-04-x64')
      end
    end

    context 'overridden options' do
      config = {
        image: 'debian-7-0-x64',
        flavor: '1gb',
        ssh_key_ids: '5678',
        username: 'admin',
        port: '2222',
        server_name: 'puppy',
        region: 'ams1',
        flavor: '1GB'
      }

      let(:config) { config }

      config.each do |key, value|
        it "it uses the overridden #{key} option" do
          expect(driver[key]).to eq(value)
        end
      end
    end
  end

  describe '#create' do
    let(:server) do
      double(id: '1234', wait_for: true,
             public_ip_address: '1.2.3.4')
    end
    let(:driver) do
      d = Kitchen::Driver::Digitalocean.new(config)
      d.instance = instance
      allow(d).to receive(:default_name).and_return('a_monkey!')
      allow(d).to receive(:create_server).and_return(server)
      allow(d).to receive(:wait_for_sshd).with('1.2.3.4').and_return(true)
      d
    end

    context 'username and API key only provided' do
      let(:config) do
        {
          digitalocean_access_token: 'access_token'
        }
      end

      it 'generates a server name in the absence of one' do
        stub_request(:get, 'https://api.digitalocean.com/v2/droplets/1234')
          .to_return(create)
        driver.create(state)
        expect(driver[:server_name]).to eq('a_monkey!')
      end

      it 'gets a proper server ID' do
        stub_request(:get, 'https://api.digitalocean.com/v2/droplets/1234')
          .to_return(create)
        driver.create(state)
        expect(state[:server_id]).to eq('1234')
      end

      it 'gets a proper hostname (IP)' do
        stub_request(:get, 'https://api.digitalocean.com/v2/droplets/1234')
          .to_return(create)
        driver.create(state)
        expect(state[:hostname]).to eq('1.2.3.4')
      end
    end
  end

  describe '#destroy' do
    let(:server_id) { '12345' }
    let(:hostname) { 'example.com' }
    let(:state) { { server_id: server_id, hostname: hostname } }
    let(:server) { double(:nil? => false, :destroy => true) }
    let(:servers) { double(get: server) }
    let(:compute) { double(servers: servers) }

    let(:driver) do
      d = Kitchen::Driver::Digitalocean.new(config)
      d.instance = instance
      allow(d).to receive(:compute).and_return(compute)
      d
    end

    context 'a live server that needs to be destroyed' do
      it 'destroys the server' do
        stub_request(:delete, 'https://api.digitalocean.com/v2/droplets/12345')
          .to_return(delete)
        expect(state).to receive(:delete).with(:server_id)
        expect(state).to receive(:delete).with(:hostname)
        driver.destroy(state)
      end
    end

    context 'no server ID present' do
      let(:state) { Hash.new }

      it 'does nothing' do
        allow(driver).to receive(:compute)
        expect(driver).not_to receive(:compute)
        expect(state).not_to receive(:delete)
        driver.destroy(state)
      end
    end

    context 'a server that was already destroyed' do
      let(:servers) do
        s = double('servers')
        allow(s).to receive(:get).with('12345').and_return(nil)
        s
      end
      let(:compute) { double(servers: servers) }
      let(:driver) do
        d = Kitchen::Driver::Digitalocean.new(config)
        d.instance = instance
        allow(d).to receive(:compute).and_return(compute)
        d
      end

      it 'does not try to destroy the server again' do
        stub_request(:delete, 'https://api.digitalocean.com/v2/droplets/12345')
          .to_return(delete)
        allow_message_expectations_on_nil
        driver.destroy(state)
      end
    end
  end

  # describe '#create_server' do
  #   let(:config) do
  #     {
  #       server_name: 'test server',
  #       image: 'debian-7-0-x64',
  #       size: '2gb',
  #       region: 'nyc3',
  #       private_networking: true,
  #       ssh_key_ids: '1234'
  #     }
  #   end
  #   before(:each) do
  #     @expected = config.merge(name: config[:server_name])
  #     @expected.delete_if do |k, _v|
  #       k == :server_name
  #     end
  #   end
  #   let(:servers) do
  #     s = double('servers')
  #     allow(s).to receive(:create) { |arg| arg }
  #     s
  #   end
  #   let(:create_server) { double(servers: servers) }
  #   let(:driver) do
  #     d = Kitchen::Driver::Digitalocean.new(config)
  #     d.instance = instance
  #     allow(d).to receive(:create_server).and_return(create_server)
  #     d
  #   end

  #   it 'creates the server using a compute connection' do
  #     expect(driver.send(:create_server)).to eq(@expected)
  #   end
  # end

  describe '#default_name' do
    before(:each) do
      allow(Etc).to receive(:getlogin).and_return('user')
      allow(Socket).to receive(:gethostname).and_return('host')
    end

    it 'generates a name' do
      expect(driver.default_name).to match(
        /^potatoes-user-(\S*)-host/)
    end
  end
end

# vim: ai et ts=2 sts=2 sw=2 ft=ruby
