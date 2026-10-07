struct Parameter:
    var name: String
    var type_name: String

    def __init__(out self, name: String, type_name: String):
        self.name = name
        self.type_name = type_name


struct BinaryExpr:
    var left: String
    var operator: String
    var right: String

    def __init__(
        out self,
        left: String,
        operator: String,
        right: String
    ):
        self.left = left
        self.operator = operator
        self.right = right


struct ReturnStmt:
    var value: BinaryExpr

    def __init__(out self, value: BinaryExpr):
        self.value = value


struct Function:
    var name: String
    var parameters: List[Parameter]
    var return_type: String
    var body: ReturnStmt

    def __init__(
        out self,
        name: String,
        parameters: List[Parameter],
        return_type: String,
        body: ReturnStmt
    ):
        self.name = name
        self.parameters = parameters
        self.return_type = return_type
        self.body = body