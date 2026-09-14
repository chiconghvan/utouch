def format_socket_data(task_type, *datas):
    """Put data in correct format to send to zxtouch tweak

    :param task_type: type of the task
    :param datas: data to be sent
    :return: ZXTouch socket data in correct format
    """
    return (str(task_type) + (";;".join(str(x) for x in datas)) + "\r\n").encode()

def decode_socket_data(data):
    """Decode the socket data

    :param data: socket data
    :return: a tuple. (success?, error message)
    """
    if not data:
        return (False, "empty response from zxtouch")

    try:
        data = data.decode(errors="replace")
    except AttributeError:
        data = str(data)
    data = data.rstrip("\r\n")
    if not data:
        return (False, "empty response from zxtouch")

    temp = data.split(";;")
    if temp[0] != "0":
        err_message = "Unknown err because zxtouch doesn't send any error info to python"
        if len(temp) >= 2:
            err_message = temp[1]
        return (False, err_message)
    return (True, temp[1:])





