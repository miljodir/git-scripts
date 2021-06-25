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
    public class GroupGetter
    {
        public async Task<List<GroupId>> GetGroups()
        {

            HttpClient _client;
            string baseUrl = "https://git.equinor.com/api/v4/";
            // "https://k8s.sdp.statoil.no/api/v4/"

            _client = new HttpClient();
            // _client.DefaultRequestHeaders.Add("Private-Token", pat);
            _client.BaseAddress = new Uri(baseUrl);

            // Could be simplified to not use an object.
            var model = new Base();
            model.visibility = "internal";

            string url = $"{baseUrl}groups/?per_page=100";

            HttpResponseMessage response = await _client.GetAsync(url);
            var responseBody = await response.Content.ReadAsStringAsync();
            List<Group> groupModel = JsonConvert.DeserializeObject<List<Group>>(responseBody);

            var groupIdList = new List<GroupId>();

            foreach (var i in groupModel)
            {
                var j = new GroupId();
                j.id = i.id;
                j.visibility = "internal";
                groupIdList.Add(j);
            }
            var nb = groupIdList;
            return groupIdList;
        }
    }
}
