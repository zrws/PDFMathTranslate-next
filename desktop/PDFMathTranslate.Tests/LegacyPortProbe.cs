using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace PDFMathTranslateLauncher;

internal static class Program
{
    internal static string Home="";
    internal static List<string> Logs=[];
    internal static bool CanConnect(string host,int port)=>false;
    internal static void AppendLog(string line){lock(Logs)Logs.Add(line);}
}

internal static class LegacyPortProbe
{
    internal static async Task Run(string[] args)
    {
        if(args.Length!=4)throw new ArgumentException("python, source/packages, repo, new evidence root required");
        var evidence=Path.GetFullPath(args[3]);if(Directory.Exists(evidence))throw new IOException("evidence exists");Directory.CreateDirectory(evidence);
        Program.Home=Path.Combine(args[2],".local","legacy-port-probe-"+Guid.NewGuid().ToString("N"));
        var listener=new TcpListener(IPAddress.Loopback,0);listener.ExclusiveAddressUse=true;listener.Start();
        var port=((IPEndPoint)listener.LocalEndpoint).Port;var requests=0;var authorization=false;
        using var cancel=new CancellationTokenSource();
        var observer=Task.Run(async()=>{try{while(!cancel.IsCancellationRequested){using var connection=await listener.AcceptTcpClientAsync(cancel.Token);Interlocked.Increment(ref requests);using var stream=connection.GetStream();var bytes=new byte[8192];var count=await stream.ReadAsync(bytes,cancel.Token);authorization|=Encoding.ASCII.GetString(bytes,0,count).Contains("Authorization:",StringComparison.OrdinalIgnoreCase);await stream.WriteAsync(Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"),cancel.Token);}}catch(OperationCanceledException){}catch(SocketException)when(cancel.IsCancellationRequested){}});
        var ready=false;var childExit=0;
        try{using var runner=new BackendRunner(args[0],"unused",args[1],port,args[2]);ready=runner.StartAndWaitReady();childExit=runner.ExitCode;await Task.Delay(250);}
        finally{cancel.Cancel();listener.Stop();await observer;}
        var passed=!ready&&childExit!=0&&requests==0&&!authorization&&!Program.Logs.Any(x=>x.StartsWith("WebUI ready:"));
        File.WriteAllText(Path.Combine(evidence,"result.json"),JsonSerializer.Serialize(new{passed,port,actual_child_exit=childExit,ready,requests_received=requests,authorization_received=authorization,driver_pid=Environment.ProcessId,home=Program.Home,scope="real production BackendRunner + real compatibility Python, occupied loopback listener; no token content recorded"},new JsonSerializerOptions{WriteIndented=true}));
        if(!passed)throw new Exception("occupied legacy port received a request or bootstrap was accepted");
    }
}
