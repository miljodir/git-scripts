using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Net.Http;
using System.Net;
using Newtonsoft.Json;
using System.IO;

namespace gitlab_manipulator
{
    public class Program {

        public static async Task Main()
        {
            HttpClient _client;
            string baseUrl = "https://git.equinor.com/api/v4/";
            // //"https://k8s.sdp.statoil.no/api/v4/"

            // add your PAT from Gitlab here
            string pat = "x";

            _client = new HttpClient();
            _client.DefaultRequestHeaders.Add("Private-Token", pat);
            _client.BaseAddress = new Uri(baseUrl);

            // Could be simplified to not use an object.
            var model = new Base();
            model.visibility = "internal";

            int counter = 0;
            string line;
               string fileloc = Path.Combine("C:\\", "idlist.txt");

            // Read the file and display it line by line.  
            // content should be output from "select id from projects where visibility_level = 20;"
            System.IO.StreamReader file =
                new System.IO.StreamReader(fileloc);
            while ((line = file.ReadLine()) != null)
            {
                System.Console.WriteLine(line);
                counter++;

                // Manipulate projects
                string projectUrlEnding = $"projects/{line}";
                string url1 = $"{baseUrl}{projectUrlEnding}/?private_token={pat}&visibility=internal";
                var projectBody = new StringContent(JsonConvert.SerializeObject(model), Encoding.UTF8, "application/json");

                HttpResponseMessage response = await _client.PutAsync(url1, projectBody);
                var projectResponseBody = await response.Content.ReadAsStringAsync();
            }

            file.Close();

            // Manipulate groups only after all projects are internal.

            // Get a list of groups
            var getter = new GroupGetter();
            var groupList = await getter.GetGroups();

            foreach (var i in groupList)
            {
                string groupUrlEnding = $"groups/{i.id}";
                string url2 = $"{baseUrl}{groupUrlEnding}/?private_token={pat}&visibility=internal";

                var groupBody = new StringContent(JsonConvert.SerializeObject(model), Encoding.UTF8, "application/json");
                HttpResponseMessage groupResponse = await _client.PutAsync(url2, groupBody);
                var groupResponsebody = await groupResponse.Content.ReadAsStringAsync();

            }
            string igfdsa = "a";
        }
    }
}
