r"""
Mixed integer linear programming
"""

include "../ext/stdsage.pxi"
include "../ext/interrupt.pxi"

class MixedIntegerLinearProgram:
    r"""
    The ``MixedIntegerLinearProgram`` class is the link between Sage, linear
    programming (LP) and  mixed integer programming (MIP) solvers. See the
    Wikipedia article on
    `linear programming <http://en.wikipedia.org/wiki/Linear_programming>`_
    for further information. A mixed integer program consists of variables,
    linear constraints on these variables, and an objective function which is
    to be maximised or minimised under these constraints. An instance of
    ``MixedIntegerLinearProgram`` also requires the information on the
    direction of the optimization.

    A ``MixedIntegerLinearProgram`` (or ``LP``) is defined as a maximization
    if ``maximization=True`` and is a minimization if ``maximization=False``.

    INPUT:

    - ``maximization``

      - When set to ``True`` (default), the ``MixedIntegerLinearProgram`` is
        defined as a maximization.
      - When set to ``False``, the ``MixedIntegerLinearProgram`` is defined as
        a minimization.

    EXAMPLES::

         sage: ### Computation of a maximum stable set in Petersen's graph
         sage: g = graphs.PetersenGraph()
         sage: p = MixedIntegerLinearProgram(maximization=True)
         sage: b = p.new_variable()
         sage: p.set_objective(sum([b[v] for v in g]))
         sage: for (u,v) in g.edges(labels=None):
         ...       p.add_constraint(b[u] + b[v], max=1)
         sage: p.set_binary(b)
         sage: p.solve(objective_only=True)     # optional - requires Glpk or COIN-OR/CBC
         4.0
    """

    def __init__(self, maximization=True):
        r"""
        Constructor for the ``MixedIntegerLinearProgram`` class.

        INPUT:

        - ``maximization``

          - When set to ``True`` (default), the ``MixedIntegerLinearProgram``
            is defined as a maximization.
          - When set to ``False``, the ``MixedIntegerLinearProgram`` is
            defined as a minimization.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram(maximization=True)
        """
        try:
            from sage.numerical.mipCoin import solveCoin
            self._default_solver = "Coin"
        except:
            try:
                from sage.numerical.mipGlpk import solve_glpk
                self._default_solver = "GLPK"
            except:
                self._default_solver = None

        # List of all the MIPVariables linked to this instance of
        # MixedIntegerLinearProgram
        self._mipvariables = []

        # Associates an index to the variables
        self._variables = {}

        # contains the variables' values when
        # solve(objective_only=False) is called
        self._values = {}

        # Several constants
        self.__BINARY = 1
        self.__REAL = -1
        self.__INTEGER = 0

        # ######################################################
        # The informations of a Linear Program
        #
        # - name
        # - maximization
        # - objective
        #    --> name
        #    --> i
        #    --> values
        # - variables
        #   --> names
        #   --> type
        #   --> bounds
        #       --> min
        #       --> max
        # - constraints
        #   --> names
        #   --> matrix
        #       --> i
        #       --> j
        #       --> values
        #   --> bounds
        #       --> min
        #       --> max
        #
        # The Constraint matrix being almost always sparse, it is stored
        # as a list of positions (i,j) in the matrix with an associated value.
        #
        # This is how matrices are exchanged in GLPK's or Cbc's libraries
        # By storing the data this way, we do no have to convert them
        # ( too often ) and this process is a bit faster.
        #
        # ######################################################


        self._name = None
        self._maximization = maximization
        self._objective_i = None
        self._objective_values = None
        self._objective_name = None
        self._variables_name = []
        self._variables_type = []
        self._variables_bounds_min = []
        self._variables_bounds_max = []
        self._constraints_name = []
        self._constraints_matrix_i = []
        self._constraints_matrix_j = []
        self._constraints_matrix_values = []
        self._constraints_bounds_max = []
        self._constraints_bounds_min = []


    def __repr__(self):
         r"""
         Returns a short description of the ``MixedIntegerLinearProgram``.

         EXAMPLE::

             sage: p = MixedIntegerLinearProgram()
             sage: v = p.new_variable()
             sage: p.add_constraint(v[1] + v[2], max=2)
             sage: print p
             Mixed Integer Program ( maximization, 2 variables, 1 constraints )
         """
         return "Mixed Integer Program "+("\""+self._name+"\"" if self._name!=None else "")+" ( " + \
             ( "maximization" if self._maximization else "minimization" ) + \
             ", " + str(len(self._variables)) + " variables, " +  \
             str(len(self._constraints_bounds_min)) + " constraints )"

    def __eq__(self,p):
        r"""
        Test of equality.

        INPUT:

        - ``p`` -- an instance of ``MixedIntegerLinearProgram`` to be tested
          against ``self``.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.add_constraint(v[1] + v[2], max=2)
            sage: p == loads(dumps(p))
            True
            sage: p2 = loads(dumps(p))
            sage: p2.add_constraint(2*v[1] + 3*v[2], max=1)
            sage: p == p2
            False
        """

        return (
            self._name == p._name and
            self._maximization == p._maximization and
            self._objective_i == p._objective_i and
            self._objective_values == p._objective_values and
            self._objective_name == p._objective_name and
            self._variables_name == p._variables_name and
            self._variables_type == p._variables_type and
            self._variables_bounds_min == p._variables_bounds_min and
            self._variables_bounds_max == p._variables_bounds_max and
            self._constraints_name == p._constraints_name and
            self._constraints_matrix_i == p._constraints_matrix_i and
            self._constraints_matrix_j == p._constraints_matrix_j and
            self._constraints_matrix_values == p._constraints_matrix_values and
            self._constraints_bounds_max == p._constraints_bounds_max
            )

    def __getitem__(self, v):
        r"""
        Returns the symbolic variable corresponding to the key
        from a default dictionary.

        It returns the element asked, and otherwise creates it.
        If necessary, it also creates the default dictionary.

        This method lets the user define LinearProgram without having to
        define independent dictionaries when it is not necessary for him.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: p.set_objective(p['x'] + p['z'])
            sage: p['x']
            x0
        """

        try:
            return self._default_mipvariable[v]
        except AttributeError:
            self._default_mipvariable = self.new_variable()
            return self._default_mipvariable[v]

    def set_problem_name(self,name):
        r"""
        Sets the name of the ``MixedIntegerLinearProgram``.

        INPUT:

        - ``name`` -- A string representing the name of the
          ``MixedIntegerLinearProgram``.

        EXAMPLE::

            sage: p=MixedIntegerLinearProgram()
            sage: p.set_problem_name("Test program")
            sage: p
            Mixed Integer Program "Test program" ( maximization, 0 variables, 0 constraints )
        """

        self._name=name

    def set_objective_name(self,name):
        r"""
        Sets the name of the objective function.

        INPUT:

        - ``name`` -- A string representing the name of the
          objective function.

        EXAMPLE::

            sage: p=MixedIntegerLinearProgram()
            sage: p.set_objective_name("Objective function")
        """

        self._objective_name=name

    def _update_variables_name(self):
        r"""
        Updates the names of the variables.

        Only called before writing the Problem to a MPS or LP file.

        EXAMPLE::

            sage: p=MixedIntegerLinearProgram()
            sage: v=p.new_variable(name="Test")
            sage: v[5]+v[99]
            x0 + x1
            sage: p._update_variables_name()
        """

        self._variables_name=['']*len(self._variables)
        for v in self._mipvariables:
            v._update_variables_name()


    def new_variable(self, vtype=-1, dim=1,name=None):
        r"""
        Returns an instance of ``MIPVariable`` associated
        to the current instance of ``MixedIntegerLinearProgram``.

        A new variable ``x`` is defined by::

            sage: p = MixedIntegerLinearProgram()
            sage: x = p.new_variable()

        It behaves exactly as a usual dictionary would. It can use any key
        argument you may like, as ``x[5]`` or ``x["b"]``, and has methods
        ``items()`` and ``keys()``.

        Any of its fields exists, and is uniquely defined.

        INPUT:

        - ``dim`` (integer) -- Defines the dimension of the dictionary.
          If ``x`` has dimension `2`, its fields will be of the form
          ``x[key1][key2]``.
        - ``vtype`` (integer) -- Defines the type of the variables
          (default is ``REAL``).
        - ``name`` (string) -- A name for the variable
          ( default is V+number )

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: # available types are p.__REAL, p.__INTEGER and p.__BINARY
            sage: x = p.new_variable(vtype=p.__REAL)
            sage: y = p.new_variable(dim=2)
            sage: p.add_constraint(x[2] + y[3][5], max=2)
        """
        if name==None:
            name="V"+str(len(self._mipvariables))
        v=MIPVariable(self, vtype, dim=dim,name=name)
        self._mipvariables.append(v)
        return v

    def constraints(self):
        r"""
        Returns the list of constraints.

        This function returns the constraints as a list
        of tuples ``(linear_function,min_bound,max_bound)``, representing
        the constraint:

        .. MATH::

            \text{min\_bound}
            \leq
            \text{linear\_function}
            \leq
            \text{max\_bound}

        Variables ``min_bound`` (respectively ``max_bound``) is set
        to ``None`` when the function has no lower ( respectively upper )
        bound.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram(maximization=True)
            sage: x = p.new_variable()
            sage: p.set_objective(x[1] + 5*x[2])
            sage: p.add_constraint(x[1] + 2/10*x[2], max=4)
            sage: p.add_constraint(15/10*x[1]+3*x[2], max=4)
            sage: p.constraints()
            [(x0 + 1/5*x1, None, 4), (3/2*x0 + 3*x1, None, 4)]
        """

        d = [0]*len(self._variables)
        for (v,id) in self._variables.iteritems():
            d[id]=v

        constraints=[0]*len(self._constraints_bounds_min)
        for (i,j,value) in zip(self._constraints_matrix_i,self._constraints_matrix_j,self._constraints_matrix_values):
            constraints[i]+=value*d[j]
        return zip(constraints,self._constraints_bounds_min,self._constraints_bounds_max)


    def show(self):
        r"""
        Displays the ``MixedIntegerLinearProgram`` in a human-readable
        way.

        EXAMPLES::

            sage: p = MixedIntegerLinearProgram()
            sage: x = p.new_variable()
            sage: p.set_objective(x[1] + x[2])
            sage: p.add_constraint(-3*x[1] + 2*x[2], max=2)
            sage: p.show()
            Maximization:
              x0 + x1
            Constraints:
              -3*x0 + 2*x1 <= 2
            Variables:
              x0 is a real variable (min=0.0, max=+oo)
              x1 is a real variable (min=0.0, max=+oo)
        """

        inv_variables = [0]*len(self._variables)
        for (v,id) in self._variables.iteritems():
            inv_variables[id]=v


        value = ( "Maximization:\n"
                  if self._maximization
                  else "Minimization:\n" )
        value+="  "
        if self._objective_i==None:
            value+="Undefined"
        else:
            value+=str(sum([inv_variables[i]*c for (i,c) in zip(self._objective_i, self._objective_values)]))

        value += "\nConstraints:"
        for (c,min,max) in self.constraints():
            value += "\n  " + (str(min)+" <= " if min!=None else "")+str(c)+(" <= "+str(max) if max!=None else "")
        value += "\nVariables:"
        for _,v in sorted([(str(x),x) for x in self._variables.keys()]):

            value += "\n  " + str(v) + " is"
            if self.is_integer(v):
                value += " an integer variable"
            elif self.is_binary(v):
                value += " an boolean variable"
            else:
                value += " a real variable"
            value += " (min=" + \
                ( str(self.get_min(v))
                  if self.get_min(v) != None
                  else "-oo" ) + \
                ", max=" + \
                ( str(self.get_max(v))
                  if self.get_max(v) != None
                  else "+oo" ) + \
                ")"
        print value

    def write_mps(self,filename,modern=True):
        r"""
        Write the linear program as a MPS file.

        This function export the problem as a MPS file.

        INPUT:

        - ``filename`` -- The file in which you want the problem
          to be written.

        - ``modern`` -- Lets you choose between Fixed MPS and Free MPS

            - ``True`` -- Outputs the problem in Free MPS
            - ``False`` -- Outputs the problem in Fixed MPS

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: x = p.new_variable()
            sage: p.set_objective(x[1] + x[2])
            sage: p.add_constraint(-3*x[1] + 2*x[2], max=2,name="OneConstraint")
            sage: p.write_mps(SAGE_TMP+"/lp_problem.mps") # optional - requires GLPK

        For information about the MPS file format :
        http://en.wikipedia.org/wiki/MPS_%28format%29
        """

        try:
            from sage.numerical.mipGlpk import write_mps
        except:
            raise NotImplementedError("You need GLPK installed to use this function. To install it, you can type in Sage: install_package('glpk')")

        self._update_variables_name()
        write_mps(self, filename, modern)


    def write_lp(self,filename):
        r"""
        Write the linear program as a LP file.

        This function export the problem as a LP file.

        INPUT:

        - ``filename`` -- The file in which you want the problem
          to be written.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: x = p.new_variable()
            sage: p.set_objective(x[1] + x[2])
            sage: p.add_constraint(-3*x[1] + 2*x[2], max=2)
            sage: p.write_lp(SAGE_TMP+"/lp_problem.lp") # optional - requires GLPK

        For more information about the LP file format :
        http://lpsolve.sourceforge.net/5.5/lp-format.htm
        """
        try:
            from sage.numerical.mipGlpk import write_lp
        except:
            raise NotImplementedError("You need GLPK installed to use this function. To install it, you can type in Sage: install_package('glpk')")

        self._update_variables_name()
        write_lp(self, filename)


    def get_values(self, *lists):
        r"""
        Return values found by the previous call to ``solve()``.

        INPUT:

        - Any instance of ``MIPVariable`` (or one of its elements),
          or lists of them.

        OUTPUT:

        - Each instance of ``MIPVariable`` is replaced by a dictionary
          containing the numerical values found for each
          corresponding variable in the instance.
        - Each element of an instance of a ``MIPVariable`` is replaced
          by its corresponding numerical value.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: x = p.new_variable()
            sage: y = p.new_variable(dim=2)
            sage: p.set_objective(x[3] + y[2][9] + x[5])
            sage: p.add_constraint(x[3] + y[2][9] + 2*x[5], max=2)
            sage: p.solve() # optional - requires Glpk or COIN-OR/CBC
            2.0
            sage: #
            sage: # Returns the optimal value of y[2][9]
            sage: p.get_values(y[2][9]) # optional - requires Glpk or COIN-OR/CBC
            2.0
            sage: #
            sage: # Returns a dictionary identical to x
            sage: # containing values for the corresponding
            sage: # variables
            sage: x_sol = p.get_values(x)
            sage: x_sol.keys()
            [3, 5]
            sage: #
            sage: # Obviously, it also works with
            sage: # variables of higher dimension
            sage: y_sol = p.get_values(y)
            sage: #
            sage: # We could also have tried :
            sage: [x_sol, y_sol] = p.get_values(x, y)
            sage: # Or
            sage: [x_sol, y_sol] = p.get_values([x, y])
        """
        val = []
        for l in lists:
            if isinstance(l, MIPVariable):
                if l.depth() == 1:
                    c = {}
                    for (k,v) in l.items():
                        c[k] = self._values[v] if self._values.has_key(v) else None
                    val.append(c)
                else:
                    c = {}
                    for (k,v) in l.items():
                        c[k] = self.get_values(v)
                    val.append(c)
            elif isinstance(l, list):
                if len(l) == 1:
                    val.append([self.get_values(l[0])])
                else:
                    c = []
                    [c.append(self.get_values(ll)) for ll in l]
                    val.append(c)
            elif self._variables.has_key(l):
                val.append(self._values[l])
        if len(lists) == 1:
            return val[0]
        else:
            return val

    def set_objective(self,obj):
        r"""
        Sets the objective of the ``MixedIntegerLinearProgram``.

        INPUT:

        - ``obj`` -- A linear function to be optimized.
          ( can also be set to ``None`` or ``0`` when just
          looking for a feasible solution )

        EXAMPLE:

        Let's solve the following linear program::

            Maximize:
              x + 5 * y
            Constraints:
              x + 0.2 y       <= 4
              1.5 * x + 3 * y <= 4
            Variables:
              x is Real (min = 0, max = None)
              y is Real (min = 0, max = None)

        This linear program can be solved as follows::

            sage: p = MixedIntegerLinearProgram(maximization=True)
            sage: x = p.new_variable()
            sage: p.set_objective(x[1] + 5*x[2])
            sage: p.add_constraint(x[1] + 2/10*x[2], max=4)
            sage: p.add_constraint(1.5*x[1]+3*x[2], max=4)
            sage: p.solve()     # optional - requires Glpk or COIN-OR/CBC
            6.6666666666666661
            sage: p.set_objective(None)
            sage: p.solve() #optional - requires Glpk or COIN-OR/CBC
            0.0
        """


        self._objective_i = []
        self._objective_values = []

        # If the objective is None, or a constant, we want to remember
        # that the objective function has been defined ( the user did not
        # forget it ). In some LP problems, you just want a feasible solution
        # and do not care about any function being optimal.

        try:
            f = self._NormalForm(obj)
        except:
            return None

        f.pop(0,0)

        for (v,coeff) in f.iteritems():
            self._objective_i.append(self._variables[v])
            self._objective_values.append(coeff)

    def add_constraint(self, linear_function, max=None, min=None, name=None):
        r"""
        Adds a constraint to the ``MixedIntegerLinearProgram``.

        INPUT:

        - ``consraint`` -- A linear function.
        - ``max`` -- An upper bound on the constraint (set to ``None``
          by default).
        - ``min`` -- A lower bound on the constraint.
        - ``name`` -- A name for the constraint.

        EXAMPLE:

        Consider the following linear program::

            Maximize:
              x + 5 * y
            Constraints:
              x + 0.2 y       <= 4
              1.5 * x + 3 * y <= 4
            Variables:
              x is Real (min = 0, max = None)
              y is Real (min = 0, max = None)

        This linear program can be solved as follows::

            sage: p = MixedIntegerLinearProgram(maximization=True)
            sage: x = p.new_variable()
            sage: p.set_objective(x[1] + 5*x[2])
            sage: p.add_constraint(x[1] + 0.2*x[2], max=4)
            sage: p.add_constraint(1.5*x[1] + 3*x[2], max=4)
            sage: p.solve()     # optional - requires Glpk or COIN-OR/CBC
            6.6666666666666661

        TESTS::

            sage: p=MixedIntegerLinearProgram()
            sage: p.add_constraint(sum([]),min=2)
        """


        if linear_function==0:
            return None

        # In case a null constraint is given ( see tests )
        try:
            f = self._NormalForm(linear_function)
        except:
            return None

        self._constraints_name.append(name)

        constant_coefficient = f.pop(0,0)

        # We do not want to ignore the constant coefficient
        max = (max-constant_coefficient) if max != None else None
        min = (min-constant_coefficient) if min != None else None


        c=len(self._constraints_bounds_min)

        for (v,coeff) in f.iteritems():
            self._constraints_matrix_i.append(c)
            self._constraints_matrix_j.append(self._variables[v])
            self._constraints_matrix_values.append(coeff)

        self._constraints_bounds_max.append(max)
        self._constraints_bounds_min.append(min)



    def set_binary(self, e):
        r"""
        Sets a variable or a ``MIPVariable`` as binary.

        INPUT:

        - ``e`` -- An instance of ``MIPVariable`` or one of
          its elements.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: x = p.new_variable()
            sage: # With the following instruction, all the variables
            sage: # from x will be binary.
            sage: p.set_binary(x)
            sage: p.set_objective(x[0] + x[1])
            sage: p.add_constraint(-3*x[0] + 2*x[1], max=2)
            sage: #
            sage: # It is still possible, though, to set one of these
            sage: # variables as real while keeping the others as they are.
            sage: p.set_real(x[3])
        """
        if isinstance(e, MIPVariable):
            e.vtype = self.__BINARY
            if e.depth() == 1:
                for v in e.values():
                    self._variables_type[self._variables[v]] = self.__BINARY
            else:
                for v in e.keys():
                    self.set_binary(e[v])
        elif self._variables.has_key(e):
            self._variables_type[self._variables[e]] = self.__BINARY
        else:
            raise ValueError("e must be an instance of MIPVariable or one of its elements.")

    def is_binary(self, e):
        r"""
        Tests whether the variable ``e`` is binary. Variables are real by
        default.

        INPUT:

        - ``e`` -- A variable (not a ``MIPVariable``, but one of its elements.)

        OUTPUT:

        ``True`` if the variable ``e`` is binary; ``False`` otherwise.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.set_objective(v[1])
            sage: p.is_binary(v[1])
            False
            sage: p.set_binary(v[1])
            sage: p.is_binary(v[1])
            True
        """

        if self._variables_type[self._variables[e]] == self.__BINARY:
            return True
        return False

    def set_integer(self, e):
        r"""
        Sets a variable or a ``MIPVariable`` as integer.

        INPUT:

        - ``e`` -- An instance of ``MIPVariable`` or one of
          its elements.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: x = p.new_variable()
            sage: # With the following instruction, all the variables
            sage: # from x will be integers
            sage: p.set_integer(x)
            sage: p.set_objective(x[0] + x[1])
            sage: p.add_constraint(-3*x[0] + 2*x[1], max=2)
            sage: #
            sage: # It is still possible, though, to set one of these
            sage: # variables as real while keeping the others as they are.
            sage: p.set_real(x[3])
        """
        if isinstance(e, MIPVariable):
            e.vtype = self.__INTEGER
            if e.depth() == 1:
                for v in e.values():
                    self._variables_type[self._variables[v]] = self.__INTEGER
            else:
                for v in e.keys():
                    self.set_integer(e[v])
        elif self._variables.has_key(e):
            self._variables_type[self._variables[e]] = self.__INTEGER
        else:
            raise ValueError("e must be an instance of MIPVariable or one of its elements.")

    def is_integer(self, e):
        r"""
        Tests whether the variable is an integer. Variables are real by
        default.

        INPUT:

        - ``e`` -- A variable (not a ``MIPVariable``, but one of its elements.)

        OUTPUT:

        ``True`` if the variable ``e`` is an integer; ``False`` otherwise.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.set_objective(v[1])
            sage: p.is_integer(v[1])
            False
            sage: p.set_integer(v[1])
            sage: p.is_integer(v[1])
            True
        """

        if self._variables_type[self._variables[e]] == self.__INTEGER:
            return True
        return False

    def set_real(self,e):
        r"""
        Sets a variable or a ``MIPVariable`` as real.

        INPUT:

        - ``e`` -- An instance of ``MIPVariable`` or one of
          its elements.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: x = p.new_variable()
            sage: # With the following instruction, all the variables
            sage: # from x will be real (they are by default, though).
            sage: p.set_real(x)
            sage: p.set_objective(x[0] + x[1])
            sage: p.add_constraint(-3*x[0] + 2*x[1], max=2)
            sage: #
            sage: # It is still possible, though, to set one of these
            sage: # variables as binary while keeping the others as they are.
            sage: p.set_binary(x[3])
        """
        if isinstance(e, MIPVariable):
            e.vtype = self.__REAL
            if e.depth() == 1:
                for v in e.values():
                    self._variables_type[self._variables[v]] = self.__REAL
            else:
                for v in e.keys():
                    self.set_real(e[v])
        elif self._variables.has_key(e):
            self._variables_type[self._variables[e]] = self.__REAL
        else:
            raise ValueError("e must be an instance of MIPVariable or one of its elements.")

    def is_real(self, e):
        r"""
        Tests whether the variable is real. Variables are real by default.

        INPUT:

        - ``e`` -- A variable (not a ``MIPVariable``, but one of its elements.)

        OUTPUT:

        ``True`` if the variable is real; ``False`` otherwise.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.set_objective(v[1])
            sage: p.is_real(v[1])
            True
            sage: p.set_binary(v[1])
            sage: p.is_real(v[1])
            False
            sage: p.set_real(v[1])
            sage: p.is_real(v[1])
            True
        """

        if self._variables_type[self._variables[e]] == self.__REAL:
            return True
        return False

    def solve(self, solver=None, log=False, objective_only=False):
        r"""
        Solves the ``MixedIntegerLinearProgram``.

        INPUT:

        - ``solver`` -- 3 solvers should be available through this class:

          - GLPK (``solver="GLPK"``). See the
            `GLPK <http://www.gnu.org/software/glpk/>`_ web site.

          - COIN Branch and Cut  (``solver="Coin"``). See the
            `COIN-OR <http://www.coin-or.org>`_ web site.

          - CPLEX (``solver="CPLEX"``). See the
            `CPLEX <http://www.ilog.com/products/cplex/>`_ web site.
            An interface to CPLEX is not yet implemented.

          ``solver`` should then be equal to one of ``"GLPK"``, ``"Coin"``,
          ``"CPLEX"``, or ``None``. If ``solver=None`` (default), the default
          solver is used (COIN if available, GLPK otherwise).

        - ``log`` -- This boolean variable indicates whether progress should
          be printed during the computations.

        - ``objective_only`` -- Boolean variable.

          - When set to ``True``, only the objective function is returned.
          - When set to ``False`` (default), the optimal numerical values
            are stored (takes computational time).

        OUTPUT:

        The optimal value taken by the objective function.

        EXAMPLES:

        Consider the following linear program::

            Maximize:
              x + 5 * y
            Constraints:
              x + 0.2 y       <= 4
              1.5 * x + 3 * y <= 4
            Variables:
              x is Real (min = 0, max = None)
              y is Real (min = 0, max = None)

        This linear program can be solved as follows::

            sage: p = MixedIntegerLinearProgram(maximization=True)
            sage: x = p.new_variable()
            sage: p.set_objective(x[1] + 5*x[2])
            sage: p.add_constraint(x[1] + 0.2*x[2], max=4)
            sage: p.add_constraint(1.5*x[1] + 3*x[2], max=4)
            sage: p.solve()           # optional - requires Glpk or COIN-OR/CBC
            6.6666666666666661
            sage: p.get_values(x)     # optional random - requires Glpk or COIN-OR/CBC
            {0: 0.0, 1: 1.3333333333333333}

         Computation of a maximum stable set in Petersen's graph::

            sage: g = graphs.PetersenGraph()
            sage: p = MixedIntegerLinearProgram(maximization=True)
            sage: b = p.new_variable()
            sage: p.set_objective(sum([b[v] for v in g]))
            sage: for (u,v) in g.edges(labels=None):
            ...       p.add_constraint(b[u] + b[v], max=1)
            sage: p.set_binary(b)
            sage: p.solve(objective_only=True)     # optional - requires Glpk or COIN-OR/CBC
            4.0

        TESTS::

            sage: g = graphs.PetersenGraph()
            sage: p = MixedIntegerLinearProgram(maximization=True)
            sage: b = p.new_variable()
            sage: p.set_objective(sum([b[v] for v in g]))
            sage: p.set_binary(b)
            sage: p.solve(solver='GLPK', objective_only=True) # optional - requires GLPK
            Traceback (most recent call last):
            ...
            NotImplementedError: ...
        """
        if self._objective_i == None:
            raise ValueError("No objective function has been defined.")

        if solver == None:
            solver = self._default_solver

        if solver == None:
            raise ValueError("There does not seem to be any Linear Program solver installed. Please visit http://www.sagemath.org/packages/optional/ to install CBC or GLPK.")
        elif solver == "Coin":
            try:
                from sage.numerical.mipCoin import solveCoin
            except:
                raise NotImplementedError("Coin/CBC is not installed and cannot be used to solve this MixedIntegerLinearProgram. To install it, you can type in Sage: install_package('cbc')")
            _sig_on
            r = solveCoin(self, log=log, objective_only=objective_only)
            _sig_off
            return r
        elif solver == "GLPK":
            try:
                from sage.numerical.mipGlpk import solve_glpk
            except:
                raise NotImplementedError("GLPK is not installed and cannot be used to solve this MixedIntegerLinearProgram. To install it, you can type in Sage: install_package('glpk')")
            _sig_on
            r = solve_glpk(self, log=log, objective_only=objective_only)
            _sig_off
            return r
        elif solver == "CPLEX":
            raise NotImplementedError("The support for CPLEX is not implemented yet.")
        else:
            raise NotImplementedError("'solver' should be set to 'GLPK', 'Coin', 'CPLEX' or None (in which case the default one is used).")

    def _NormalForm(self, exp):
        r"""
        Returns a dictionary built from the linear function.

        INPUT:

        - ``exp`` -- The expression representing a linear function.

        OUTPUT:

        A dictionary whose keys are the variables and whose
        values are their coefficients. The value corresponding to key
        `0` is the constant coefficient.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: nf = p._NormalForm(v[0] + v[1])
            sage: nf[0], nf[v[0]], nf[v[1]]
            (0, 1, 1)
        """

        d2={}

        for v in exp.variables():
            d2[v]=exp.coefficient(v)

        d2[0] = exp-sum([c*v for (v,c) in d2.iteritems()])

        return d2

    def _add_element_to_ring(self, vtype):
        r"""
        Creates a new variable from the main ``InfinitePolynomialRing``.

        INPUT:

        - ``vtype`` (integer) -- Defines the type of the variables
          (default is ``REAL``).

        OUTPUT:

        - The newly created variable.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: len(p._variables_type)
            0
            sage: p._add_element_to_ring(p.__REAL)
            x0
            sage: len(p._variables_type)
            1
        """

        from sage.calculus.calculus import var
        v = var('x'+str(len(self._variables)))

        self._variables[v] = len(self._variables)
        self._variables_type.append(vtype)
        self._variables_bounds_min.append(0)
        self._variables_bounds_max.append(None)
        return v

    def set_min(self, v, min):
        r"""
        Sets the minimum value of a variable.

        INPUT:

        - ``v`` -- a variable (not a ``MIPVariable``, but one of its
          elements).
        - ``min`` -- the minimum value the variable can take.
          When ``min=None``, the variable has no lower bound.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.set_objective(v[1])
            sage: p.get_min(v[1])
            0.0
            sage: p.set_min(v[1],6)
            sage: p.get_min(v[1])
            6.0
        """
        self._variables_bounds_min[self._variables[v]] = min

    def set_max(self, v, max):
        r"""
        Sets the maximum value of a variable.

        INPUT

        - ``v`` -- a variable (not a ``MIPVariable``, but one of its
          elements).
        - ``max`` -- the maximum value the variable can take.
          When ``max=None``, the variable has no upper bound.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.set_objective(v[1])
            sage: p.get_max(v[1])
            sage: p.set_max(v[1],6)
            sage: p.get_max(v[1])
            6.0
        """

        self._variables_bounds_max[self._variables[v]] = max

    def get_min(self, v):
        r"""
        Returns the minimum value of a variable.

        INPUT:

        - ``v`` -- a variable (not a ``MIPVariable``, but one of its elements).

        OUTPUT:

        Minimum value of the variable, or ``None`` if
        the variable has no lower bound.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.set_objective(v[1])
            sage: p.get_min(v[1])
            0.0
            sage: p.set_min(v[1],6)
            sage: p.get_min(v[1])
            6.0
        """
        return float(self._variables_bounds_min[self._variables[v]]) if self._variables_bounds_min[self._variables[v]] != None else None

    def get_max(self, v):
        r"""
        Returns the maximum value of a variable.

        INPUT:

        - ``v`` -- a variable (not a ``MIPVariable``, but one of its elements).

        OUTPUT:

        Maximum value of the variable, or ``None`` if
        the variable has no upper bound.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.set_objective(v[1])
            sage: p.get_max(v[1])
            sage: p.set_max(v[1],6)
            sage: p.get_max(v[1])
            6.0
        """
        return float(self._variables_bounds_max[self._variables[v]])  if self._variables_bounds_max[self._variables[v]] != None else None

class MIPSolverException(Exception):
    r"""
    Exception raised when the solver fails.
    """

    def __init__(self, value):
        r"""
        Constructor for ``MIPSolverException``.

        ``MIPSolverException`` is the exception raised when the solver fails.

        EXAMPLE::

            sage: from sage.numerical.mip import MIPSolverException
            sage: MIPSolverException("Error")
            MIPSolverException()

        TESTS::

            sage: # No continuous solution
            sage: #
            sage: p=MixedIntegerLinearProgram()
            sage: v=p.new_variable()
            sage: p.add_constraint(v[0],max=5.5)
            sage: p.add_constraint(v[0],min=7.6)
            sage: p.set_objective(v[0])
            sage: #
            sage: # Tests of GLPK's Exceptions
            sage: #
            sage: p.solve(solver="GLPK") # optional - requires GLPK
            Traceback (most recent call last):
            ...
            MIPSolverException: 'GLPK : Solution is undefined'
            sage: #
            sage: #
            sage: # No integer solution
            sage: #
            sage: p=MixedIntegerLinearProgram()
            sage: v=p.new_variable()
            sage: p.add_constraint(v[0],max=5.6)
            sage: p.add_constraint(v[0],min=5.2)
            sage: p.set_objective(v[0])
            sage: p.set_integer(v)
            sage: #
            sage: # Tests of GLPK's Exceptions
            sage: #
            sage: p.solve(solver="GLPK") # optional - requires GLPK
            Traceback (most recent call last):
            ...
            MIPSolverException: 'GLPK : Solution is undefined'


        """
        self.value = value

    def __str__(self):
        r"""
        Returns the value of the instance of ``MIPSolverException``.

        EXAMPLE::

            sage: from sage.numerical.mip import MIPSolverException
            sage: e = MIPSolverException("Error")
            sage: print e
            'Error'
        """
        return repr(self.value)

class MIPVariable:
    r"""
    ``MIPVariable`` is a variable used by the class
    ``MixedIntegerLinearProgram``.
    """

    def __init__(self, p, vtype, dim=1, name=None):
        r"""
        Constructor for ``MIPVariable``.

        INPUT:

        - ``p`` -- the instance of ``MixedIntegerLinearProgram`` to which the
          variable is to be linked.
        - ``vtype`` (integer) -- Defines the type of the variables
          (default is ``REAL``).
        - ``dim`` -- the integer defining the definition of the variable.
        - ``name`` -- A name for the ``MIPVariable``.

        For more informations, see the method
        ``MixedIntegerLinearProgram.new_variable``.

        EXAMPLE::

            sage: p=MixedIntegerLinearProgram()
            sage: v=p.new_variable()
        """
        self._dim = dim
        self._dict = {}
        self._p = p
        self._vtype = vtype
        self._name=name


    def __getitem__(self, i):
        r"""
        Returns the symbolic variable corresponding to the key.

        Returns the element asked, otherwise creates it.
        (When depth>1, recursively creates the variables).

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.set_objective(v[0] + v[1])
            sage: v[0]
            x0
        """
        if self._dict.has_key(i):
            return self._dict[i]
        elif self._dim == 1:
            self._dict[i] = self._p._add_element_to_ring(self._vtype)
            return self._dict[i]
        else:
            self._dict[i] = MIPVariable(self._p, self._vtype, dim=self._dim-1)
            return self._dict[i]

    def _update_variables_name(self, prefix=None):
        r"""
        Updates the names of the variables in the parent instant of ``MixedIntegerLinearProgram``.

        Only called before writing the Problem to a MPS or LP file.

        EXAMPLE::

            sage: p=MixedIntegerLinearProgram()
            sage: v=p.new_variable(name="Test")
            sage: v[5]+v[99]
            x0 + x1
            sage: p._variables_name=['']*2
            sage: v._update_variables_name()
        """

        if prefix==None:
            prefix=self._name

        if self._dim==1:
            for (k,v) in self._dict.iteritems():
                self._p._variables_name[self._p._variables[v]]=prefix+"["+str(k)+"]"
        else:
            for v in self._dict.itervalues():
                v._update_variables_name(prefix=prefix+"["+str(k)+"]")



    def __repr__(self):
        r"""
        Returns a representation of self.

        EXAMPLE::

            sage: p=MixedIntegerLinearProgram()
            sage: v=p.new_variable(dim=3)
            sage: v
            MIPVariable of dimension 3.
            sage: v[2][5][9]
            x0
            sage: v
            MIPVariable of dimension 3.
        """
        return "MIPVariable of dimension "+str(self._dim)+"."

    def keys(self):
        r"""
        Returns the keys already defined in the dictionary.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.set_objective(v[0] + v[1])
            sage: v.keys()
            [0, 1]
        """
        return self._dict.keys()

    def items(self):
        r"""
        Returns the pairs (keys,value) contained in the dictionary.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.set_objective(v[0] + v[1])
            sage: v.items()
            [(0, x0), (1, x1)]
        """
        return self._dict.items()

    def depth(self):
        r"""
        Returns the current variable's depth.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.set_objective(v[0] + v[1])
            sage: v.depth()
            1
        """
        return self._dim

    def values(self):
        r"""
        Returns the symbolic variables associated to the current dictionary.

        EXAMPLE::

            sage: p = MixedIntegerLinearProgram()
            sage: v = p.new_variable()
            sage: p.set_objective(v[0] + v[1])
            sage: v.values()
            [x0, x1]
        """
        return self._dict.values()
