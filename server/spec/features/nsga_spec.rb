# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER, THE UNITED STATES
# GOVERNMENT, OR ANY CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

require 'rails_helper'
#
# describe "RunNSGA" do
#   before :all do
#     Delayed::Job.destroy_all
#   end
#
#   it "Runs the analysis", js: true do
#     host = "#{Capybara.current_session.server.host}:#{Capybara.current_session.server.port}"
#     puts "http://#{host}"
#     APP_CONFIG['os_server_host_url'] = "http://#{host}"
#     expect(host).to match /\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3}:\d{2,5}/
#
#     h = JSON.parse(File.read('spec/files/test_model/test_model.json'), symbolize_names: true)
#
#     workdir = 'spec/files/test_model/tmp_nsga'
#     FileUtils.mkdir_p workdir unless Dir.exist? workdir
#
#     formulation = OpenStudio::Analysis.load(h)
#     formulation.analysis_type = 'nsga_nrel'
#     formulation.algorithm.set_attribute('generations', 1)
#     formulation.algorithm.set_attribute('exit_on_guideline_14', 1)
#
#     formulation.save "#{workdir}/test_model.json"
#
#     expect(Delayed::Job.count).to eq(0)
#     options = {hostname: "http://#{host}"}
#     api = OpenStudio::Analysis::ServerApi.new(options)
#     analysis_id = api.run("#{workdir}/test_model.json",
#                           'spec/files/test_model/test_model.zip',
#                           formulation.analysis_type)
#
#     expect(Delayed::Job.count).to eq(1)
#     # Use threads to emulate the multiple queues
#     threads = []
#     threads << Thread.new(1) { # analysis queue
#       expect(Delayed::Worker.new.run(Delayed::Job.first)).to eq true
#     }
#     threads << Thread.new(2) { # worker/simulations queue
#       loop do
#         j = Delayed::Job.where(queue: 'simulations').first
#         if j
#           expect(Delayed::Worker.new.run(j)).to eq true
#           # tell the analysis to stop after one simulation. This does
#           # not do an extensive test of the algorithm, just ensures that
#           # a single simulation is able to be created and run.
#           api.kill_analysis(analysis_id)
#           break
#         end
#         sleep 1
#       end
#     }
#     threads.each {|t| t.join}
#
#     expect(Delayed::Job.count).to eq(0)
#   end
# end
