using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Web.Script.Serialization;
using RTTUnitEditor.Domain;
using RTTUnitEditor.Editing;

// Independent synthetic test configuration; no reference-data inputs.
public static class AcceptanceUnits
{
    const string Note = "TEST ONLY: independently generated from RTTGame DB40 settlement test requirements; no third-party data inputs. Editor source baseline is retained, not DB40 certification.";
    static EditorSession session = new EditorSession();
    static void Set(Dictionary<string,string> fields, params string[] pairs) { for(int i=0;i<pairs.Length;i+=2) fields[pairs[i]]=pairs[i+1]; }
    static BodyDraft Body(string name, bool armor, int count) {
        var b=session.Create(armor?"ground_vehicle":"infantry");b.Name=name;b.SourceNote=Note;
        Set(b.Fields,"memberCount",count.ToString(),"roadSpeed","5","offroadPenalty","0","turnSpeed",armor?"90":"360","faction","test_only","specialization","test_only");
        if(armor) Set(b.Fields,"maximumHealth","20","offroadPenalty","0.2","weight","1","maxPassengers","0","totalLoad","0"); else b.UpdateInfantryHealth();
        string[] faces={"front","side","rear","top"};
        for(int i=0;i<4;i++) foreach(string energy in new[]{"kinetic","chemical"}) b.Fields[energy+"."+faces[i]]=armor?((i+1)*10).ToString():"6";
        if(armor)b.Installations=new List<PlatformMount>();
        return b;
    }
    static CombatDraft Weapon(string name, string ammoId, bool top) {
        var w=session.CreateCombat("weapon").Clone();w.Name=name;
        Set(w.Fields,"caliber","test_only","faction","test_only","specialization","test_only","weight","0.001","operators","1","minRange","0","maxRange","300","spread","0","aimMin","0.1","aimMax","0.1","rpm","60","consumption","1","capacity","10","reloadRule","continuous","reload","3","ignoreReduction","0","slotRule","primary");
        w.Fields["specialEquipmentWeight"]="0";
        w.AmmoIds.Add(ammoId);w.TargetTypes.AddRange(new[]{"infantry","ground_vehicle"});if(top)w.Tags.Add("top_attack");session.ApplyCombat(w,x=>true);return w;
    }
    static void Bind(string name, BodyDraft body, CombatDraft weapon) {
        var load=session.CreateLoadout().Clone();load.Name=name+" loadout";load.SourceNote=Note;
        var binding=session.CreateBinding(body.Id).Clone();binding.LoadoutId=load.Id;binding.SourceNote=Note;
        binding.Category=body.UnitType=="infantry"?"infantry":"armor";binding.ValuePoints="5";binding.DeploymentPoints="5";binding.MaximumOnField="8";binding.Icon="test_only";
        if(body.UnitType=="ground_vehicle")binding.SupplyWeight="0";
        var rel=binding.Relations;rel.Name=name;rel.MemberCount=body.Fields["memberCount"];rel.Specialization="test_only";rel.StockOwners=new List<StockOwner>();
        if(body.UnitType=="infantry")for(int i=0;i<int.Parse(rel.MemberCount);i++)rel.Members.Add(new ConfigMember());
        if(weapon!=null){
			bool vehicle=body.UnitType=="ground_vehicle";
			if(vehicle)rel.Members.Add(new ConfigMember()); // Explicit editor operator relation, not infantry HP.
            var entry=new WeaponEntry{WeaponId=weapon.Id,Quantity="1",AmmoOrder=new List<string>(weapon.AmmoIds)};
			if(vehicle){var mount=body.Installations[0];entry.MountKind=mount.Kind;entry.MountIndex=mount.Index;entry.InstallationId=mount.Id;}
            entry.Inventory[weapon.AmmoIds[0]]="40";load.Entries.Add(entry);
            rel.Roles.Add(new WeaponRole{EntryId=entry.Id,Quantity="1",Priority="0",OperatorIds=new List<string>{rel.Members[0].Id},CandidateRoleIds=new List<string>()});
            rel.StockOwners.Add(new StockOwner{EntryId=entry.Id,AmmoId=weapon.AmmoIds[0],MemberId=rel.Members[0].Id,Quantity="40"});
        }
        session.ApplyConfiguration(binding,load);
    }
    public static int Main(string[] args) {
        try {
            if(args.Length!=2)throw new ArgumentException("output JSON and diagnostics JSON required");
            var a=session.CreateCombat("ammo").Clone();a.Name="TEST ONLY settlement HE";
            Set(a.Fields,"caliber","test_only","faction","test_only","specialization","test_only","specialNote",Note,"damageType","chemical","category","HE","damage","1","penetration","50","speed","300","blast","4","suppression","7","moduleDamage","0","supplyCost","0","missingCost","0");
            session.ApplyCombat(a,x=>true);
            var normal=Weapon("TEST ONLY normal HE",a.Id,false);var top=Weapon("TEST ONLY top HE",a.Id,true);
            Bind("TEST ONLY normal shooter",Body("TEST ONLY shooter body",false,12),normal);
            Bind("TEST ONLY top shooter",Body("TEST ONLY top shooter body",false,12),top);
            Bind("TEST ONLY infantry target",Body("TEST ONLY target body",false,12),null);
            Bind("TEST ONLY armor target",Body("TEST ONLY armor body",true,1),null);
            var suppress=session.CreateCombat("ammo").Clone();suppress.Name="TEST ONLY zero-damage suppression";
            Set(suppress.Fields,"caliber","test_only","faction","test_only","specialization","test_only","specialNote",Note,"damageType","chemical","category","HE","damage","0","penetration","50","speed","300","blast","4","suppression","320","moduleDamage","0","supplyCost","0","missingCost","0");
            session.ApplyCombat(suppress,x=>true);
            Bind("TEST ONLY suppression shooter",Body("TEST ONLY suppression body",false,12),Weapon("TEST ONLY suppression weapon",suppress.Id,false));
            var modules=session.CreateCombat("ammo").Clone();modules.Name="TEST ONLY zero-damage module hit";
            Set(modules.Fields,"caliber","test_only","faction","test_only","specialization","test_only","specialNote",Note,"damageType","chemical","category","HEAT","damage","0","penetration","50","speed","300","blast","0","suppression","0","moduleDamage","100","supplyCost","0","missingCost","0");
            session.ApplyCombat(modules,x=>true);
            Bind("TEST ONLY module shooter",Body("TEST ONLY module body",false,12),Weapon("TEST ONLY module weapon",modules.Id,false));
			foreach(bool mechanical in new[]{false,true}){
				string suffix=mechanical?"mechanical":"manual";
				var w=Weapon("TEST ONLY vehicle "+suffix,a.Id,false).Clone();
				Set(w.Fields,"slotRule","vehicle_slot","aimMin","2","aimMax","2","capacity","2");
				if(mechanical){w.Tags.Add("mechanical_loading");w.Fields["reload"]="4";}
				session.ApplyCombat(w,x=>true);
				var body=Body("TEST ONLY armed "+suffix+" body",true,1);
				body.Installations.Add(new PlatformMount{Kind="hull",Index="1"});
				Bind("TEST ONLY armed "+suffix+" vehicle",body,w);
			}
            session.Save(args[0]);session.Reload();
            var diagnostics=session.Bindings.Select(b=>new{ name=b.Relations.Name,id=b.Id,report=session.ValidateConfiguration(b.Id)}).ToArray();
            if(diagnostics.Any(x=>!x.report.Ready))throw new InvalidOperationException("Configuration incomplete after reload");
            File.WriteAllText(args[1],new JavaScriptSerializer().Serialize(new{testOnly=true,source=Note,configurations=diagnostics}));
            Console.WriteLine("RTTUnitEditor shared core: saved/reloaded eight TEST ONLY configurations; no validation errors.");return 0;
        }catch(Exception e){Console.Error.WriteLine(e);return 1;}
    }
}
