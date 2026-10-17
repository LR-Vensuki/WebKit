#include "config.h"
#include "Tests/IPC/IPCTestUtilities.h"
#include "Helpers/Test.h"
#include <mach/mach.h>
#include <memory>
#include <wtf/Scope.h>
#include <wtf/threads/BinarySemaphore.h>

namespace TestWebKitAPI {

TEST(ConnectionFlushAquaWebKit, PendingMachMessageMustFinishBeforeFlush)
{
    WTF::initializeMainThread();
    auto identifiers = IPC::Connection::createConnectionIdentifierPair();
    ASSERT_TRUE(identifiers);
    mach_port_t receivePort = identifiers->server.port;
    Ref server = IPC::Connection::createServerConnection(WTF::move(identifiers->server));
    Ref client = IPC::Connection::createClientConnection(IPC::Connection::Identifier { WTF::move(identifiers->client) });
    Ref serverClient = MockConnectionClient::create();
    Ref clientClient = MockConnectionClient::create();
    ASSERT_TRUE(server->open(serverClient));
    ASSERT_TRUE(client->open(clientClient));
    // Complete the native connection handshake before withholding receiver progress.
    client->send(MockTestMessage1 { }, 0);
    EXPECT_EQ(serverClient->waitForMessage(5_s).destinationID, 0u);
    mach_port_limits_t limits { 1 };
    ASSERT_EQ(KERN_SUCCESS, mach_port_set_attributes(mach_task_self(), receivePort, MACH_PORT_LIMITS_INFO,
        reinterpret_cast<mach_port_info_t>(&limits), MACH_PORT_LIMITS_INFO_COUNT));

    auto receiverPaused = std::make_shared<BinarySemaphore>();
    auto releaseReceiver = std::make_shared<BinarySemaphore>();
    auto senderFinished = std::make_shared<BinarySemaphore>();
    bool paused = true;
    auto cleanup = makeScopeExit([&] {
        if (paused)
            releaseReceiver->signal();
        client->invalidate();
        server->invalidate();
        serverClient->takeMessages();
        clientClient->takeMessages();
    });
    server->dispatchOnReceiveQueueForTesting([receiverPaused, releaseReceiver] {
        receiverPaused->signal();
        releaseReceiver->wait();
    });
    ASSERT_TRUE(receiverPaused->waitFor(5_s));
    client->send(MockTestMessage1 { }, 1);
    client->send(MockTestMessage1 { }, 2);
    // The sender has attempted both sends: one is in the full kernel queue and
    // the final encoder is now held only by Connection's pending Mach retry.
    client->dispatchOnReceiveQueueForTesting([senderFinished] { senderFinished->signal(); });
    ASSERT_TRUE(senderFinished->waitFor(5_s));
    mach_port_status_t status { };
    mach_msg_type_number_t count = MACH_PORT_RECEIVE_STATUS_COUNT;
    ASSERT_EQ(KERN_SUCCESS, mach_port_get_attributes(mach_task_self(), receivePort, MACH_PORT_RECEIVE_STATUS,
        reinterpret_cast<mach_port_info_t>(&status), &count));
    ASSERT_EQ(status.mps_qlimit, 1u);
    ASSERT_EQ(status.mps_msgcount, 1u);
    ASSERT_EQ(client->flushSentMessages(100_ms), IPC::Error::Timeout);

    paused = false;
    releaseReceiver->signal();
    EXPECT_EQ(client->flushSentMessages(5_s), IPC::Error::NoError);
    client->invalidate();
    EXPECT_EQ(serverClient->waitForMessage(5_s).destinationID, 1u);
    EXPECT_EQ(serverClient->waitForMessage(5_s).destinationID, 2u);
    if (!serverClient->gotDidClose())
        EXPECT_TRUE(serverClient->waitForDidClose(5_s));
}

}
