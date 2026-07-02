package jason.stdlib;

import jason.asSemantics.TransitionSystem;
import jason.asSemantics.Unifier;
import jason.asSyntax.Literal;
import jason.asSyntax.ListTermImpl;
import jason.asSyntax.NumberTerm;
import jason.asSyntax.Term;

import static jason.asSyntax.ASSyntax.createAtom;
import static jason.asSyntax.ASSyntax.createNumber;

public class setpoint_local extends embedded.mas.bridges.jacamo.defaultEmbeddedInternalAction {

        private static Double referenceYaw;

        @Override
        public Object execute(TransitionSystem ts, Unifier un, Term[] args) throws Exception {
            ListTermImpl parameters = new ListTermImpl();
            if (args.length == 3) {
                addLocalSetpoint(ts, parameters,
                    numberArg(args[0], "forward"),
                    numberArg(args[1], "right"),
                    numberArg(args[2], "up"));
            } else if (args.length == 1 && args[0] instanceof ListTermImpl && ((ListTermImpl) args[0]).size() == 3) {
                ListTermImpl values = (ListTermImpl) args[0];
                addLocalSetpoint(ts, parameters,
                    numberArg(values.get(0), "forward"),
                    numberArg(values.get(1), "right"),
                    numberArg(values.get(2), "up"));
            } else {
                for (Term t : args) parameters.add(t);
            }

            Term[] arguments = new Term[3];
            arguments[0] = createAtom("sample_roscore");
            arguments[1] = createAtom(this.getClass().getSimpleName());
            arguments[2] = parameters;
            return super.execute(ts, un, arguments);
        }

        private static void addLocalSetpoint(
                TransitionSystem ts,
                ListTermImpl parameters,
                double forward,
                double right,
                double up) throws Exception {
            LocalPose pose = currentLocalPose(ts);
            double yaw = captureOrReuseReferenceYaw(pose.yaw);

            double deltaX = (forward * Math.cos(yaw)) + (right * Math.sin(yaw));
            double deltaY = (forward * Math.sin(yaw)) - (right * Math.cos(yaw));

            parameters.add(createNumber(pose.x + deltaX));
            parameters.add(createNumber(pose.y + deltaY));
            parameters.add(createNumber(pose.z + up));
            parameters.add(createNumber(yaw));
        }

        public static synchronized void resetReferenceYaw() {
            referenceYaw = null;
        }

        private static synchronized double captureOrReuseReferenceYaw(double yaw) {
            if (referenceYaw == null) {
                referenceYaw = yaw;
            }
            return referenceYaw.doubleValue();
        }

        private static LocalPose currentLocalPose(TransitionSystem ts) throws Exception {
            for (Literal belief : ts.getAg().getBB()) {
                if (("position".equals(belief.getFunctor()) || "nav_pose_local".equals(belief.getFunctor()))
                        && belief.getArity() >= 1) {
                    return poseFromBelief(belief);
                }
            }
            throw new IllegalStateException(
                "setpoint_local(Forward, Right, Up) requires nav_pose_local(...) from /mavros/local_position/pose");
        }

        private static LocalPose poseFromBelief(Literal belief) throws Exception {
            Literal pose = findNestedLiteral(belief, "pose");
            Literal position = asLiteral(pose.getTerm(0), "position");
            Literal orientation = asLiteral(pose.getTerm(1), "orientation");

            double x = numberFromAxis(position, 0);
            double y = numberFromAxis(position, 1);
            double z = numberFromAxis(position, 2);

            double qx = numberFromAxis(orientation, 0);
            double qy = numberFromAxis(orientation, 1);
            double qz = numberFromAxis(orientation, 2);
            double qw = numberFromAxis(orientation, 3);

            double yaw = Math.atan2(
                2.0 * ((qw * qz) + (qx * qy)),
                1.0 - (2.0 * ((qy * qy) + (qz * qz))));

            return new LocalPose(x, y, z, yaw);
        }

        private static Literal asLiteral(Term term, String name) {
            if (!(term instanceof Literal)) {
                throw new IllegalStateException("Expected " + name + " literal inside local pose belief");
            }
            return (Literal) term;
        }

        private static Literal findNestedLiteral(Literal literal, String functor) {
            if (functor.equals(literal.getFunctor())) {
                return literal;
            }
            for (int i = 0; i < literal.getArity(); i++) {
                Term term = literal.getTerm(i);
                if (term instanceof Literal) {
                    Literal child = findNestedLiteral((Literal) term, functor);
                    if (child != null) {
                        return child;
                    }
                }
            }
            return null;
        }

        private static double numberFromAxis(Literal literal, int axisIndex) throws Exception {
            return numberArg(asLiteral(literal.getTerm(axisIndex), literal.getFunctor() + " axis").getTerm(0), literal.getFunctor());
        }

        private static double numberArg(Term arg, String name) throws Exception {
            if (!(arg instanceof NumberTerm)) {
                throw new IllegalArgumentException("setpoint_local requires numeric " + name + " argument");
            }
            return ((NumberTerm) arg).solve();
        }

        private static class LocalPose {
            final double x;
            final double y;
            final double z;
            final double yaw;

            LocalPose(double x, double y, double z, double yaw) {
                this.x = x;
                this.y = y;
                this.z = z;
                this.yaw = yaw;
            }
        }
}
