using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace gitlab_manipulator
{
    public class Base
    {
        public string visibility { get; set; }

    }

    public class GroupId : Base
    {
        public int id { get; set; }
    }

    public class List
    {
        public List<Group> list { get; set; }
    }

    public class Group : Base
    {
        public int id { get; set; }
        public string web_url { get; set; }
        public string name { get; set; }
        public string path { get; set; }
        public string description { get; set; }
        public bool lfs_enabled { get; set; }
        public object avatar_url { get; set; }
        public bool request_access_enabled { get; set; }
        public string full_name { get; set; }
        public string full_path { get; set; }
        public object parent_id { get; set; }

    }

}
