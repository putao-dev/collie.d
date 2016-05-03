module app;

import core.thread;

import std.datetime;
import std.stdio;
import std.functional;

import collie.socket;
import collie.channel;
import collie.bootstrap.client;

alias Pipeline!(UniqueBuffer, ubyte[]) EchoPipeline;

ClientBootStrap!EchoPipeline client;
EventLoop loop;

class EchoHandler : HandlerAdapter!(UniqueBuffer, ubyte[])
{
public:
    override void read(Context ctx, UniqueBuffer msg)
    {
         writeln("Read data : ", cast(string) msg.data, "   the length is ", msg.length());
    }

    void callBack(ubyte[] data, uint len)
    {
        writeln("\t writed data : ", cast(string) data, "   the length is ", len);
    }

    override void timeOut(Context ctx)
    {
        writeln("clent beat time Out!");
        string data = Clock.currTime().toSimpleString();
        write(ctx, cast(ubyte[])data , &callBack);
    }
}

class EchoPipelineFactory : PipelineFactory!EchoPipeline
{
public:
    override EchoPipeline newPipeline(TCPSocket sock)
    {
        auto pipeline = EchoPipeline.create();
        pipeline.addBack(new TCPSocketHandler(sock));
        pipeline.addBack(new EchoHandler());
        pipeline.finalize();
        return pipeline;
    }
}


void main()
{
    loop = new EventLoop();
    client = new ClientBootStrap!EchoPipeline(loop);
    client.heartbeatTimeOut(2).setPipelineFactory(new EchoPipelineFactory()).connect("127.0.0.1",8094);
    loop.run();
    
    writeln("APP Stop!");
}
