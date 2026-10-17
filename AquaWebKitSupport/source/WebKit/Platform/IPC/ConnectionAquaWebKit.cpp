#include "config.h"
#include "Connection.h"

namespace IPC {

void Connection::didFailToSendOutgoingMessage()
{
    Locker locker { m_outgoingMessagesLock };
    m_didFailToSendOutgoingMessage = true;
    m_outgoingMessagesEmptyCondition.notifyAll();
}

}
